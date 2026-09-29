"""MobileNetV3-Small 전이학습 -> .tflite (PC / Colab 에서 실행 권장).

  python train_mobilenet.py --data dataset_old data_new --out rps_model.tflite

--data 폴더마다 scissors/ rock/ paper/ 하위 폴더가 있어야 한다.
클래스 순서는 common.CLASSES (0 scissors, 1 rock, 2 paper) 로 고정 -> 게임 코드와 일치.
val 은 촬영 회차(파일명 '<세션ID>_번호.jpg' 의 세션ID) 단위로 떼어낸다.
연속 프레임은 서로 거의 같아서, 무작위로 섞어 나누면 val 정확도가 부풀려지기 때문.
"""
import argparse
import random
from collections import defaultdict
from pathlib import Path

import numpy as np
import tensorflow as tf

from common import CLASSES, IMG_SIZE

EXTS = {'.jpg', '.jpeg', '.png', '.bmp'}


def list_files(dirs):
    """-> {group_key: [(path, label), ...]}"""
    groups = defaultdict(list)
    for d in dirs:
        for label, cls in enumerate(CLASSES):
            folder = Path(d) / cls
            if not folder.is_dir():
                print(f'  [warn] {folder} 없음')
                continue
            for p in folder.iterdir():
                if p.suffix.lower() in EXTS:
                    # collect.py 형식이면 세션 단위, 아니면 파일 하나가 한 그룹
                    key = (d, p.stem.split('_')[0]) if '_' in p.stem else (d, p.stem)
                    groups[key].append((str(p), label))
    return groups


def split(groups, val_ratio, seed):
    keys = list(groups)
    random.Random(seed).shuffle(keys)
    total = sum(len(v) for v in groups.values())
    train, val = [], []
    for k in keys:
        (val if len(val) < total * val_ratio else train).extend(groups[k])
    if not train or not val:
        raise SystemExit('train/val 분할 실패: 데이터가 너무 적습니다')
    return train, val


def make_ds(items, batch, training):
    paths = [p for p, _ in items]
    labels = [l for _, l in items]
    ds = tf.data.Dataset.from_tensor_slices((paths, labels))
    if training:
        ds = ds.shuffle(len(items), reshuffle_each_iteration=True)

    def load(path, label):
        img = tf.io.decode_image(tf.io.read_file(path), channels=3, expand_animations=False)
        img = tf.image.resize(img, (IMG_SIZE, IMG_SIZE))   # 0~255 float, RGB (추론 코드와 동일)
        return img, label

    ds = ds.map(load, num_parallel_calls=tf.data.AUTOTUNE)
    if training:
        aug = tf.keras.Sequential([
            tf.keras.layers.RandomFlip('horizontal'),          # 왼손/오른손
            tf.keras.layers.RandomRotation(0.08, fill_mode='constant', fill_value=255.0),
            tf.keras.layers.RandomZoom(0.1, fill_mode='constant', fill_value=255.0),
            tf.keras.layers.RandomBrightness(0.2, value_range=(0, 255)),
            tf.keras.layers.RandomContrast(0.2),
        ])
        ds = ds.map(lambda x, y: (tf.clip_by_value(aug(x, training=True), 0, 255), y),
                    num_parallel_calls=tf.data.AUTOTUNE)
    return ds.batch(batch).prefetch(tf.data.AUTOTUNE)


def build_model():
    # include_preprocessing=True(기본값): 모델 안에서 0~255 입력을 정규화 -> 추론 코드는 그대로 0~255 입력
    base = tf.keras.applications.MobileNetV3Small(
        input_shape=(IMG_SIZE, IMG_SIZE, 3), include_top=False, weights='imagenet',
        pooling='avg', include_preprocessing=True)
    base.trainable = False
    inp = tf.keras.Input((IMG_SIZE, IMG_SIZE, 3))
    x = base(inp, training=False)   # BatchNorm 통계 고정
    x = tf.keras.layers.Dropout(0.2)(x)
    out = tf.keras.layers.Dense(len(CLASSES), activation='softmax')(x)
    return tf.keras.Model(inp, out), base


def confusion(model, ds):
    cm = np.zeros((len(CLASSES), len(CLASSES)), int)
    for x, y in ds:
        pred = np.argmax(model.predict(x, verbose=0), 1)
        for t, p in zip(y.numpy(), pred):
            cm[t, p] += 1
    print('confusion matrix (행=정답, 열=예측):', CLASSES)
    for c, row in zip(CLASSES, cm):
        print(f'  {c:9s}', row)
    print(f'  val accuracy: {np.trace(cm) / cm.sum():.3f}')


def export(model, out, quant):
    # dynamic: 가중치만 int8 (입출력은 float) -> 게임 코드 수정 없이 사용, 크기 약 1/4.
    # 전체 int8 양자화는 MobileNetV3 + ai-edge-litert 2.2.0 XNNPACK 에서 로딩이 실패해 제외.
    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    if quant == 'dynamic':
        conv.optimizations = [tf.lite.Optimize.DEFAULT]
    Path(out).write_bytes(conv.convert())
    print(f'saved {out} ({Path(out).stat().st_size / 1e6:.2f} MB, quant={quant})')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', nargs='+', required=True, help='데이터 폴더들 (기존 + 새로 찍은 것)')
    ap.add_argument('--out', default='rps_model.tflite')
    ap.add_argument('--epochs', type=int, default=10, help='head 만 학습하는 epoch')
    ap.add_argument('--finetune-epochs', type=int, default=5, help='base 뒷부분까지 푸는 epoch (0이면 생략)')
    ap.add_argument('--batch', type=int, default=32)
    ap.add_argument('--val-ratio', type=float, default=0.2)
    ap.add_argument('--quant', choices=['none', 'dynamic'], default='dynamic')
    ap.add_argument('--seed', type=int, default=42)
    args = ap.parse_args()

    groups = list_files(args.data)
    train_items, val_items = split(groups, args.val_ratio, args.seed)
    for name, items in (('train', train_items), ('val', val_items)):
        cnt = np.bincount([l for _, l in items], minlength=len(CLASSES))
        print(f'{name}: {len(items)}장', dict(zip(CLASSES, cnt.tolist())))

    train_ds = make_ds(train_items, args.batch, True)
    val_ds = make_ds(val_items, args.batch, False)
    model, base = build_model()

    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3), loss='sparse_categorical_crossentropy',
                  metrics=['accuracy'])
    model.fit(train_ds, validation_data=val_ds, epochs=args.epochs)

    if args.finetune_epochs > 0:
        base.trainable = True
        for layer in base.layers[:-30]:       # 뒤쪽 30개 층만 학습
            layer.trainable = False
        for layer in base.layers:             # BatchNorm 은 계속 고정 (소량 데이터에서 불안정)
            if isinstance(layer, tf.keras.layers.BatchNormalization):
                layer.trainable = False
        model.compile(optimizer=tf.keras.optimizers.Adam(1e-5), loss='sparse_categorical_crossentropy',
                  metrics=['accuracy'])
        model.fit(train_ds, validation_data=val_ds, epochs=args.finetune_epochs)

    confusion(model, val_ds)
    model.save(Path(args.out).with_suffix('.keras'))
    export(model, args.out, args.quant)


if __name__ == '__main__':
    main()
