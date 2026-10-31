#!/usr/bin/env python3
"""冻结一份研究配置（字典 §3 research_manifests）。

用法示例（所有值都必须显式给出，脚本不提供默认值）：

    python3 scripts/seed_manifest.py \\
        --study-id pinyintone-2026-ma \\
        --app-version 1.0 --build-number 17 \\
        --lexicon-version lex-2026.10 --scoring-version scoring-v5 \\
        --feedback-version fb-1.0 --advice-policy-version advice-1.0 \\
        --survey-version survey-1.0 --consent-version consent-1.0 \\
        --eligibility-version eligibility-2.0 \\
        --collection-start 2026-10-20T08:00:00+01:00 \\
        --collection-end   2026-10-25T08:00:00+01:00

联调用的测试配置加 `--test`（材料可以是草稿，参与者一律 is_test=true）。

现场实测轮（2026-10-28 起）另有三项：
- `--field-protocol`：绑定前测/训练/后测的协议（默认读 App 携带的 field_protocol.json）。
- `--audio-upload`：接收录音。**只能**与写明上传录音的同意文本（consent-2.0）一起用，
  反过来 consent-2.0 也必须开录音——同意书上写了会上传，配置却不收，或者反过来，都不行。
- `--collection-end open`：不设结束日期（研究者 2026-10-28 定为「不限时间」）。
  结束时用 close_manifest.py 把终点改成当下，这是已冻结配置唯一允许的改动。

研究者的审定记录在 `research_materials_approval.json`。列在里面却没有审定日期的材料
（同意文本、纳入规则、实测协议）只能冻结成测试配置；开发方不得代填审定。

为什么不给默认值：manifest 决定评分、词库、提示与问卷版本，
猜一个默认值会把数据归到错误的配置下，而这种错误在导出时极难发现。

**采集窗口由研究者与导师确定**（需求 R04）：起止时间都必须显式给出、带时区，
脚本不再按固定 14 天推算终点，也不替研究者选日期。
`collection_start_at` 须是新版**实际公开可用**之后的时点，不填预计上线时间。

**正式配置的门槛**（需求 R03）：同意文本未审定、问卷或译文是 draft、
纳入规则是 draft、词库有未核对的词条——任何一条成立都只能冻结成测试配置。
已冻结的配置不原地改写；规则或材料变了就新建一份。
"""
import argparse
import json
import os
import sys
import uuid
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import research_models  # noqa: E402
from app.database import SessionLocal  # noqa: E402

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SURVEY_DIR = os.path.join(os.path.dirname(BACKEND_DIR),
                                  "PinYintone", "Resources", "Surveys")
CORPUS_DIR = os.path.join(os.path.dirname(BACKEND_DIR), "PinYintone", "Resources", "Corpus")
DEFAULT_FIELD_PROTOCOL = os.path.join(CORPUS_DIR, "field_protocol.json")
APPROVAL_FILE = os.path.join(BACKEND_DIR, "research_materials_approval.json")
# 写明「上传录音」的同意文本版本。与 --audio-upload 必须同时出现或同时不出现
AUDIO_CONSENT_VERSIONS = {"consent-2.0"}
# 「不限时间」的终点。研究者结束采集时由 close_manifest.py 改成实际时点
OPEN_END = datetime(2099, 12, 31, tzinfo=timezone.utc)
FORM_KEYS = ("background_v1", "tone_needs_v1", "usability_short_v1")
# 版本号里出现这些字样，说明材料还没到可以正式采集的状态
UNFINISHED_MARKERS = ("draft", "unpublished")


class ManifestError(ValueError):
    """配置参数不合法。信息面向运行脚本的研究者。"""


def parse_time(value: str, flag: str) -> datetime:
    try:
        t = datetime.fromisoformat(value)
    except ValueError:
        raise ManifestError(f"{flag} 不是合法的 ISO8601 时间：{value}")
    if t.tzinfo is None:
        raise ManifestError(f"{flag} 必须带时区（如 2026-10-20T08:00:00+01:00），"
                            "否则窗口边界会随服务器时区漂移")
    return t.astimezone(timezone.utc)


def load_approvals(path: str = APPROVAL_FILE) -> dict:
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except OSError:
        raise ManifestError(f"找不到审定记录：{path}")


def load_field_protocol(path: str) -> tuple[str, dict, str]:
    """读实测协议，把词条编号换成该词库下的 lexeme_version_id。

    返回 (协议版本, 写进配置的协议内容, 协议文件里的状态)。
    测试词与训练词不得重叠：后测进步会被「练过这个词」污染。
    """
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
        with open(os.path.join(CORPUS_DIR, "research_lexicon.json"), encoding="utf-8") as f:
            lexicon = json.load(f)
    except OSError as e:
        raise ManifestError(f"读不到实测协议或词库：{e}")
    versions = {e["lexemeID"]: e["lexemeVersionID"] for e in lexicon["entries"]}
    test, train = d["testWords"], d["trainingWords"]
    if not test or not train:
        raise ManifestError("实测协议的测试词与训练词都不能为空")
    overlap = set(test) & set(train)
    if overlap:
        raise ManifestError(f"测试词与训练词重叠：{sorted(overlap)}")
    missing = [w for w in test + train if w not in versions]
    if missing:
        raise ManifestError(f"实测协议里的词不在研究词库 {lexicon['lexiconVersion']} 中：{missing}")
    reps = int(d["trainingValidAttemptsPerWord"])
    if reps < 1:
        raise ManifestError("trainingValidAttemptsPerWord 至少为 1")
    return d["protocolVersion"], {
        "lexicon_version": lexicon["lexiconVersion"],
        "test_lexeme_version_ids": [versions[w] for w in test],
        "training_lexeme_version_ids": [versions[w] for w in train],
        "training_valid_attempts_per_word": reps,
    }, d.get("status", "")


def load_survey_forms(survey_dir: str) -> dict:
    """读随 App 打包的问卷定义，取出各表单的版本。

    配置绑定的必须是 App **实际携带**的那一版问卷，所以从同一份 JSON 读，
    不让运行者手敲版本号（敲错了服务端会把所有问卷拒掉）。
    """
    forms = {}
    for key in FORM_KEYS:
        path = os.path.join(survey_dir, f"{key}.json")
        try:
            with open(path, encoding="utf-8") as f:
                d = json.load(f)
        except OSError:
            raise ManifestError(f"找不到问卷定义：{path}（用 --survey-dir 指定目录）")
        forms[key] = {"form_version": d["form_version"],
                      "translation_version": d["translation_version"]}
    return forms


def formal_blockers(db, *, consent_version, eligibility_version, lexicon_version,
                    survey_forms, field_protocol_version=None, approvals=None) -> list[str]:
    """正式配置的阻塞项。空列表 = 可以冻结为正式配置。"""
    problems = []
    approvals = approvals or {}
    for kind, version, label in (("consent", consent_version, "同意文本"),
                                 ("eligibility", eligibility_version, "纳入规则"),
                                 ("field_protocol", field_protocol_version, "实测协议")):
        if version is None:
            continue
        listed = approvals.get(kind) or {}
        # 列在审定记录里却没有日期 = 等研究者审定。没列出的是本机制之前已定稿的旧材料。
        if version in listed and not listed[version]:
            problems.append(f"{label} {version} 尚未经研究者审定"
                            f"（见 research_materials_approval.json）")

    def unfinished(v):
        return any(mark in v.lower() for mark in UNFINISHED_MARKERS)

    if unfinished(consent_version):
        problems.append(f"同意文本版本 {consent_version} 尚未审定")
    if unfinished(eligibility_version):
        problems.append(f"纳入规则版本 {eligibility_version} 仍是草稿")
    if unfinished(lexicon_version):
        problems.append(f"词库版本 {lexicon_version} 仍是草稿")
    for key, spec in survey_forms.items():
        for field in ("form_version", "translation_version"):
            if unfinished(spec[field]):
                problems.append(f"问卷 {key} 的 {field}={spec[field]} 仍是草稿")

    lexemes = (db.query(research_models.ResearchLexeme)
               .filter_by(lexicon_version=lexicon_version).all())
    if not lexemes:
        problems.append(f"词库 {lexicon_version} 尚未入库（先运行 seed_lexicon.py）")
    else:
        pending = [x.lexeme_id for x in lexemes if x.review_status != "approved"]
        if pending:
            problems.append(f"词库 {lexicon_version} 有 {len(pending)}/{len(lexemes)} "
                            f"个词条未经核对：{', '.join(sorted(pending))}")
    return problems


_COMMON_SPEC = {
    "adult_required": True,
    "course_stage_any": ["hsk1", "hsk2", "hsk3"],
    # 不以新旧用户作为纳入条件（研究者已确认，V2_DECISIONS 第 15 条）
    "new_user_required": False,
}
# 纳入规则版本 → 规则内容。与 App 的 ResearchEligibility 一一对应
ELIGIBILITY_SPECS = {
    "eligibility-2.0": {**_COMMON_SPEC, "nationality_any": ["MA"],
                        "note": "语言背景不作为排除条件；prior_use_status 如实记录，不参与纳入判定"},
    # 现场实测轮：研究者 2026-10-28 定为不限国籍。国籍题照常作答、照常保存
    "eligibility-3.0": {**_COMMON_SPEC, "nationality_any": [],
                        "note": "不限国籍，国籍照常记录；语言背景不作为排除条件；"
                                "prior_use_status 如实记录，不参与纳入判定"},
}


def build_manifest(db, *, study_id, app_version, build_number, lexicon_version,
                   scoring_version, feedback_version, advice_policy_version,
                   survey_version, consent_version, eligibility_version,
                   collection_start, collection_end, survey_forms,
                   is_test=False, compatible_builds=None, post_trigger_count=5,
                   reward_rule_version=None, field_protocol=None, audio_upload=False,
                   eligibility_spec=None, approvals=None) -> research_models.ResearchManifest:
    """校验并构造一行配置（未提交）。不合法时抛 ManifestError。

    `field_protocol` 是 load_field_protocol 的返回值 (版本, 内容, 状态)，没有现场实测时为 None。
    """
    if collection_end <= collection_start:
        raise ManifestError("采集窗口的结束时间必须晚于开始时间")
    if post_trigger_count < 1:
        raise ManifestError("--post-trigger-count 至少为 1")
    if audio_upload != (consent_version in AUDIO_CONSENT_VERSIONS):
        raise ManifestError(
            "录音上传与同意文本不一致：只有写明上传录音的同意文本"
            f"（{', '.join(sorted(AUDIO_CONSENT_VERSIONS))}）才能开 --audio-upload，"
            "用了这份文本也必须开")
    if eligibility_spec is None:
        if eligibility_version not in ELIGIBILITY_SPECS:
            raise ManifestError(f"未知的纳入规则版本 {eligibility_version}；"
                                f"已知：{', '.join(sorted(ELIGIBILITY_SPECS))}")
        eligibility_spec = ELIGIBILITY_SPECS[eligibility_version]
    protocol_version, protocol, protocol_status = field_protocol or (None, None, "")
    if protocol and protocol["lexicon_version"] != lexicon_version:
        raise ManifestError(f"实测协议用的词库 {protocol['lexicon_version']} "
                            f"与 --lexicon-version {lexicon_version} 不一致")
    if not is_test:
        blockers = formal_blockers(db, consent_version=consent_version,
                                   eligibility_version=eligibility_version,
                                   lexicon_version=lexicon_version,
                                   survey_forms=survey_forms,
                                   field_protocol_version=protocol_version,
                                   approvals=approvals if approvals is not None
                                   else load_approvals())
        if blockers:
            raise ManifestError(
                "以下材料尚未准备好，不能冻结为正式配置（联调请加 --test）：\n  - "
                + "\n  - ".join(blockers))

    return research_models.ResearchManifest(
        manifest_id=str(uuid.uuid4()),
        study_id=study_id,
        app_version=app_version,
        build_number=build_number,
        compatible_builds=list(compatible_builds) if compatible_builds else None,
        lexicon_version=lexicon_version,
        scoring_version=scoring_version,
        # 由技术填实际规则，作者审核（字典 §3）
        scoring_spec={
            "metric_name": "normalized_dtw",
            "unit": "dimensionless",
            "direction": "lower_better",
            "min_value": 0,
            "max_value": None,
            "pass_threshold": 0.5,
            "note": "passed 不是 metric 的纯函数：全一声词首末下滑 >3 半音会被"
                    "走向闸门判不通过。判通过请用记录里的 passed，不要按阈值重算。"
                    "参照曲线由设备端 TTS 现场合成，不保证跨设备一致。",
        },
        feedback_version=feedback_version,
        advice_policy_version=advice_policy_version,
        survey_version=survey_version,
        survey_forms=survey_forms,
        consent_version=consent_version,
        eligibility_version=eligibility_version,
        eligibility_spec=eligibility_spec,
        post_trigger_count=post_trigger_count,
        post_trigger_scope="fixed_word_result_displayed",
        reward_rule_version=reward_rule_version,
        collection_start_at=collection_start,
        collection_end_at=collection_end,
        frozen_at=datetime.now(timezone.utc),
        is_test=is_test,
        field_protocol_version=protocol_version,
        field_protocol=protocol,
        audio_upload=audio_upload,
    )


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    for name in ("study-id", "app-version", "build-number", "lexicon-version",
                 "scoring-version", "feedback-version", "advice-policy-version",
                 "survey-version", "consent-version", "eligibility-version"):
        p.add_argument(f"--{name}", required=True)
    p.add_argument("--collection-start", required=True,
                   help="采集开始（ISO8601，带时区）。须是新版实际公开可用之后的时点，不填预计日期。")
    p.add_argument("--collection-end", default="open",
                   help="采集结束（ISO8601，带时区），左闭右开。默认 open：研究参与不设时限"
                        "（研究者 2026-10-31 决定），要结束时用 close_manifest.py。")
    p.add_argument("--field-protocol", default=None, nargs="?", const=DEFAULT_FIELD_PROTOCOL,
                   help="绑定现场实测协议；不带路径时读 App 携带的 field_protocol.json")
    p.add_argument("--audio-upload", action="store_true",
                   help="接收录音。只能与写明上传录音的同意文本一起用")
    p.add_argument("--compatible-builds", nargs="*", default=None,
                   help="除 --build-number 外还允许采集的构建号（修复版本）")
    p.add_argument("--test", action="store_true",
                   help="冻结为测试配置：材料可为草稿，只下发给测试客户端，"
                        "其下参与者一律 is_test=true，正式导出默认排除")
    p.add_argument("--survey-dir", default=DEFAULT_SURVEY_DIR,
                   help="随 App 打包的问卷 JSON 所在目录，用于绑定问卷与译文版本")
    p.add_argument("--post-trigger-count", type=int, default=5,
                   help="研究者已确认为 5")
    p.add_argument("--reward-rule-version", default=None,
                   help="积分规则版本；留空则积分功能整体关闭（本轮保持关闭）")
    args = p.parse_args()

    db = SessionLocal()
    try:
        try:
            m = build_manifest(
                db,
                study_id=args.study_id, app_version=args.app_version,
                build_number=args.build_number, lexicon_version=args.lexicon_version,
                scoring_version=args.scoring_version,
                feedback_version=args.feedback_version,
                advice_policy_version=args.advice_policy_version,
                survey_version=args.survey_version, consent_version=args.consent_version,
                eligibility_version=args.eligibility_version,
                collection_start=parse_time(args.collection_start, "--collection-start"),
                collection_end=(OPEN_END if args.collection_end == "open"
                                else parse_time(args.collection_end, "--collection-end")),
                survey_forms=load_survey_forms(args.survey_dir),
                is_test=args.test, compatible_builds=args.compatible_builds,
                post_trigger_count=args.post_trigger_count,
                reward_rule_version=args.reward_rule_version,
                field_protocol=(load_field_protocol(args.field_protocol)
                                if args.field_protocol else None),
                audio_upload=args.audio_upload)
        except ManifestError as e:
            print(f"错误：{e}", file=sys.stderr)
            return 1
        # 提交后对象会从库里重新加载（SQLite 读回丢时区），先把要打印的值取出来
        start, end, forms = m.collection_start_at, m.collection_end_at, dict(m.survey_forms)
        db.add(m)
        db.commit()
        kind = "测试配置（不用于正式采集）" if m.is_test else "正式配置"
        print(f"已冻结{kind} manifest_id={m.manifest_id}")
        print(f"  study_id={m.study_id}  app={m.app_version} build={m.build_number}"
              + (f" 兼容构建={m.compatible_builds}" if m.compatible_builds else ""))
        print(f"  采集窗口 {start.isoformat()} → {end.isoformat()}"
              f"（UTC，左闭右开，共 {end - start}）")
        for key, spec in forms.items():
            print(f"  问卷 {key}: {spec['form_version']} / {spec['translation_version']}")
        if m.field_protocol_version:
            fp = m.field_protocol
            print(f"  实测协议 {m.field_protocol_version}：测试词 {len(fp['test_lexeme_version_ids'])} 个，"
                  f"训练词 {len(fp['training_lexeme_version_ids'])} 个 × "
                  f"{fp['training_valid_attempts_per_word']} 次有效录音")
        print(f"  录音上传：{'开' if m.audio_upload else '关'}")
        if end >= OPEN_END:
            print("  未设结束日期：结束采集时运行 close_manifest.py")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
