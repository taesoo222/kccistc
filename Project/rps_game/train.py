"""MobileNetV3-Small 전이학습 -> rps_model.tflite

  python train.py dataset/train                       # 학습
  python train.py dataset/train --test dataset/test   # 학습 + 시험 세트 정확도

<data>/scissors|rock|paper/*.jpg  (crop_hands.py 로 만든 224x224 손 사진)
클래스 순서는 0 scissors, 1 rock, 2 paper 로 고정 (게임 코드와 동일해야 함).
--test 를 주면: 학습 폴더 전체를 학습에 쓰고, 검증은 시험 폴더로 한다 (권장).
--test 가 없으면: 학습 폴더에서 촬영 회차(파일 이름 앞부분) 단위로 검증용을 떼어낸다.
  연속으로 찍은 사진끼리는 거의 같아서, 무작위로 나누면 val 정확도가 부풀려지기 때문.
"""
import argparse
import random
from collections import defaultdict
from pathlib import Path

import numpy as np
import tensorflow as tf

CLASSES = ['scissors', 'rock', 'paper']   # crop_hands.py 와 동일
IMG_SIZE = 224


def list_files(data_dir):
    """-> {촬영회차: [(경로, 라벨), ...]}"""
    groups = defaultdict(list)
    for label, cls in enumerate(CLASSES):
        folder = Path(data_dir) / cls
        if not folder.is_dir():
            raise SystemExit(f'{folder} 폴더가 없습니다')
        for p in sorted(folder.glob('*.jpg')):
            groups[p.stem.split('_')[0]].append((str(p), label))
    return groups


def split_by_session(groups, val_ratio, seed):
    keys = sorted(groups)
    random.Random(seed).shuffle(keys)
    total = sum(len(v) for v in groups.values())
    train, val = [], []
    for k in keys:
        (val if len(val) < total * val_ratio else train).extend(groups[k])
    if len(keys) < 2:
        print('[주의] 촬영 회차가 1개뿐이라 사진 단위로 무작위 분할합니다 (val 정확도가 실제보다 높게 나올 수 있음)')
        items = train + val
        random.Random(seed).shuffle(items)
        n_val = int(len(items) * val_ratio)
        val, train = items[:n_val], items[n_val:]
    return train, val


def make_ds(items, batch, training):
    ds = tf.data.Dataset.from_tensor_slices(([p for p, _ in items], [l for _, l in items]))
    if training:
        ds = ds.shuffle(len(items), reshuffle_each_iteration=True)

    def load(path, label):
        img = tf.io.decode_jpeg(tf.io.read_file(path), channels=3)   # RGB, 0~255
        img = tf.image.resize(img, (IMG_SIZE, IMG_SIZE))
        return img, label

    ds = ds.map(load, num_parallel_calls=tf.data.AUTOTUNE)
    if training:   # 데이터 늘리기 (학습 때만)
        aug = tf.keras.Sequential([
            tf.keras.layers.RandomFlip('horizontal'),                     # 왼손/오른손
            tf.keras.layers.RandomRotation(0.08, fill_mode='constant', fill_value=255.0),
            tf.keras.layers.RandomZoom(0.1, fill_mode='constant', fill_value=255.0),
            tf.keras.layers.RandomBrightness(0.2, value_range=(0, 255)),
            tf.keras.layers.RandomContrast(0.2),
        ])
        ds = ds.map(lambda x, y: (tf.clip_by_value(aug(x, training=True), 0, 255), y),
                    num_parallel_calls=tf.data.AUTOTUNE)
    return ds.batch(batch).prefetch(tf.data.AUTOTUNE)


def build_model():
    # include_preprocessing=True(기본값): 0~255 입력을 모델 안에서 정규화
    # -> 게임 코드는 레퍼런스처럼 0~255 RGB 를 그대로 넣으면 된다
    base = tf.keras.applications.MobileNetV3Small(
        input_shape=(IMG_SIZE, IMG_SIZE, 3), include_top=False, weights='imagenet',
        pooling='avg', include_preprocessing=True)
    base.trainable = False
    inp = tf.keras.Input((IMG_SIZE, IMG_SIZE, 3))
    x = base(inp, training=False)
    x = tf.keras.layers.Dropout(0.2)(x)
    out = tf.keras.layers.Dense(len(CLASSES), activation='softmax')(x)
    return tf.keras.Model(inp, out), base


def evaluate(model, items, title):
    cm = np.zeros((len(CLASSES), len(CLASSES)), int)
    for x, y in make_ds(items, 32, False):
        pred = np.argmax(model.predict(x, verbose=0), 1)
        for t, p in zip(y.numpy(), pred):
            cm[t, p] += 1
    print(f'\n[{title}] 정확도 {np.trace(cm) / cm.sum():.3f}  ({np.trace(cm)}/{cm.sum()})')
    print('  행=정답, 열=예측  ', '  '.join(f'{c[:4]:>4s}' for c in CLASSES))
    for c, row in zip(CLASSES, cm):
        print(f'  {c:9s}          ', '  '.join(f'{v:4d}' for v in row))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('data', help='학습 폴더 (예: dataset/train)')
    ap.add_argument('--test', help='시험 폴더 (예: dataset/test). 학습에는 쓰지 않음')
    ap.add_argument('--out', default='rps_model.tflite')
    ap.add_argument('--epochs', type=int, default=10, help='1단계: 마지막 층만 학습')
    ap.add_argument('--finetune-epochs', type=int, default=5, help='2단계: 뒤쪽 층까지 미세조정 (0이면 생략)')
    ap.add_argument('--batch', type=int, default=32)
    ap.add_argument('--val-ratio', type=float, default=0.2)
    ap.add_argument('--quant', choices=['none', 'dynamic'], default='dynamic',
                    help='dynamic: 가중치만 8비트로 줄여 파일 크기 약 1/3 (입출력은 그대로 float)')
    ap.add_argument('--seed', type=int, default=42)
    args = ap.parse_args()

    if args.test:
        # 학습 사진은 전부 학습에 쓰고, 검증은 따로 찍은 시험 사진으로
        train_items = [it for g in list_files(args.data).values() for it in g]
        val_items = [it for g in list_files(args.test).values() for it in g]
    else:
        train_items, val_items = split_by_session(list_files(args.data), args.val_ratio, args.seed)
    val_name = 'test' if args.test else 'val'
    for name, items in (('train', train_items), (val_name, val_items)):
        cnt = np.bincount([l for _, l in items], minlength=len(CLASSES))
        print(f'{name}: {len(items)}장', dict(zip(CLASSES, cnt.tolist())))

    train_ds = make_ds(train_items, args.batch, True)
    val_ds = make_ds(val_items, args.batch, False)
    model, base = build_model()

    print('\n=== 1단계: 마지막 층 학습 ===')
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss='sparse_categorical_crossentropy', metrics=['accuracy'])
    model.fit(train_ds, validation_data=val_ds, epochs=args.epochs)

    if args.finetune_epochs > 0:
        print('\n=== 2단계: 미세조정 ===')
        base.trainable = True
        for layer in base.layers[:-30]:        # 뒤쪽 30개 층만 학습
            layer.trainable = False
        for layer in base.layers:              # BatchNorm 은 고정 (적은 데이터에서 불안정)
            if isinstance(layer, tf.keras.layers.BatchNormalization):
                layer.trainable = False
        model.compile(optimizer=tf.keras.optimizers.Adam(1e-5),
                      loss='sparse_categorical_crossentropy', metrics=['accuracy'])
        model.fit(train_ds, validation_data=val_ds, epochs=args.finetune_epochs)

    evaluate(model, val_items, val_name)

    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    if args.quant == 'dynamic':
        conv.optimizations = [tf.lite.Optimize.DEFAULT]
    Path(args.out).write_bytes(conv.convert())
    print(f'\n저장: {args.out} ({Path(args.out).stat().st_size / 1e6:.2f} MB)')


if __name__ == '__main__':
    main()
