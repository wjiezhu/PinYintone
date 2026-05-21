"""嵌入式语料映射，镜像 iOS Resources/Corpus/lexemes.json。
用于声调偏误聚合（按 lexemeID 查声调）与偏误词的汉字展示。"""

CORPUS: dict[str, dict] = {
    "paobu":    {"hanzi": "跑步", "tones": [3, 4]},
    "bangzhu":  {"hanzi": "帮助", "tones": [1, 4]},
    "tingdong": {"hanzi": "听懂", "tones": [1, 3]},
    "dengdai":  {"hanzi": "等待", "tones": [3, 4]},
    "kaoshi":   {"hanzi": "考试", "tones": [3, 4]},
    "gaosu":    {"hanzi": "告诉", "tones": [4, 5]},
    "xianzai":  {"hanzi": "现在", "tones": [4, 4]},
    "dianshi":  {"hanzi": "电视", "tones": [4, 4]},
    "sushe":    {"hanzi": "宿舍", "tones": [4, 4]},
    "hanzi":    {"hanzi": "汉字", "tones": [4, 4]},
    "heshui":   {"hanzi": "喝水", "tones": [1, 3]},
    "shenti":   {"hanzi": "身体", "tones": [1, 3]},
    "jingli":   {"hanzi": "经理", "tones": [1, 3]},
    "yisheng":  {"hanzi": "医生", "tones": [1, 1]},
    "qingchu":  {"hanzi": "清楚", "tones": [1, 5]},
    "xiuxi":    {"hanzi": "休息", "tones": [1, 5]},
    "ziji":     {"hanzi": "自己", "tones": [4, 3]},
    "canjia":   {"hanzi": "参加", "tones": [1, 1]},
    "zaocan":   {"hanzi": "早餐", "tones": [3, 1]},
    "xiangxin": {"hanzi": "相信", "tones": [1, 4]},
}


def tones_for(lexeme_id: str) -> list[int]:
    return CORPUS.get(lexeme_id, {}).get("tones", [])


def hanzi_for(lexeme_id: str) -> str:
    return CORPUS.get(lexeme_id, {}).get("hanzi", lexeme_id)
