"""research_validation 的自检（本机无 pytest，直接可执行）。"""
from app.research_validation import (validate_citation_tones, validate_metric_value,
                                     ResearchValidationError)

def expect_error(fn, label):
    try:
        fn(); print(f"  ❌ {label}：本应拒绝却通过了"); return False
    except ResearchValidationError:
        print(f"  ✅ {label}：已拒绝"); return True

ok = True
print("citation_tones：")
assert validate_citation_tones([4, 0]) == [4, 0]
print("  ✅ [4,0] 告诉 通过")
assert validate_citation_tones([1, 2, 3, 4, 0]) == [1, 2, 3, 4, 0]
print("  ✅ 全部合法调值 通过")
ok &= expect_error(lambda: validate_citation_tones([4, 5]), "[4,5] 未换算的 App 编码")
ok &= expect_error(lambda: validate_citation_tones([1, 9]), "[1,9] 越界调值")
ok &= expect_error(lambda: validate_citation_tones([]), "空数组")
ok &= expect_error(lambda: validate_citation_tones([1, True]), "布尔混入")

print("metric_value：")
assert validate_metric_value(None, status="succeeded") is None
print("  ✅ NULL 通过（无观测值的正确写法）")
assert validate_metric_value(0.32, status="succeeded") == 0.32
print("  ✅ 正常分数 通过")
ok &= expect_error(lambda: validate_metric_value(-1, status="succeeded"), "-1 旧表哨兵")
ok &= expect_error(lambda: validate_metric_value(0.3, status="analysis_failed"), "失败却带分数")

print("\n全部通过" if ok else "\n有未通过项")
