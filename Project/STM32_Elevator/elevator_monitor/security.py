"""
security.py : 관리자 PIN

처음 PIN 1234, 바꾼 PIN 은 monitor_config.json 에 해시(PBKDF2-SHA256 + 솔트)로 저장
PIN 을 잊으면 monitor_config.json 을 지우면 1234 로 돌아감
"""

import hashlib
import json
import os
import secrets

# ---- 관리자 PIN ----
DEFAULT_PIN = "1234"            # 설정 파일이 없을 때 처음 PIN
PIN_MAX_FAIL = 3                # 이만큼 틀리면
PIN_LOCK_S = 30                 # 이 시간(초) 동안 잠금
CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "monitor_config.json")


def pin_hash(pin, salt_hex):
    """PIN → 해시 (PBKDF2-SHA256, 솔트 + 10만 번 반복). 설정 파일엔 이 값만 저장"""
    return hashlib.pbkdf2_hmac("sha256", pin.encode(), bytes.fromhex(salt_hex), 100_000).hex()


def load_pin_record():
    """설정 파일에서 (솔트, 해시) 읽기. 없거나 깨졌으면 기본 PIN 1234 로"""
    try:
        with open(CONFIG_FILE, encoding="utf-8") as f:
            cfg = json.load(f)
        return cfg["pin_salt"], cfg["pin_hash"], False
    except (OSError, ValueError, KeyError):
        salt = secrets.token_hex(16)
        return salt, pin_hash(DEFAULT_PIN, salt), True


def save_pin(pin):
    salt = secrets.token_hex(16)
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump({"pin_salt": salt, "pin_hash": pin_hash(pin, salt)}, f, indent=2)
    return salt, pin_hash(pin, salt)
