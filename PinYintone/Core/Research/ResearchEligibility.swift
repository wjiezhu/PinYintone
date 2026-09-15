import Foundation

/// 研究资格判定（字段字典 §1「数据边界」、§4、§14）。
///
/// **端侧筛选是硬要求**：字典明确「年龄和背景信息先在端侧筛选；仅符合条件并
/// 明确同意者写入研究库」，且「后台**不得**先收集所有用户的研究事件，
/// 再只在导出时过滤」。因此本类型的判定必须在**上报之前**发生，
/// 不能依赖服务端事后过滤。
///
/// 不符合条件或不同意的用户**正常使用全部功能**，只是不产生研究记录。
nonisolated enum ResearchEligibility {

    /// 纳入规则版本；规则变化必须递增并写入 manifest.eligibility_version
    static let version = "eligibility-1.0-draft"

    /// 课程阶段白名单。
    /// ⚠ 以三份研究文档的 `eligibility_spec` 为准（hsk1/hsk2/hsk3）——
    /// 最初需求文档写的是 HSK2/HSK3，已确认以文档为准。
    static let allowedCourseStages: Set<String> = ["hsk1", "hsk2", "hsk3"]

    /// 国籍白名单（ISO 3166-1 alpha-2）
    static let requiredNationalities: Set<String> = ["MA"]

    /// 不合格原因，对应 `research_participants.exclusion_reason`
    enum Exclusion: String {
        case age, nationality, courseStage = "course_stage"
        case withdrawn, duplicate, other
    }

    /// 判定结果。`pending` 表示背景表尚未作答，**不是**不合格——
    /// 字典要求「缺失或未知不推定满足」，同样也不推定不满足。
    enum Outcome: Equatable {
        case eligible
        case excluded(Exclusion)
        case pending
    }

    /// 背景表答案的端侧判定。
    ///
    /// - Parameters:
    ///   - isAdult: B01 是否选了 `adult`。`minor` / `prefer_not` / 跳过均不纳入
    ///   - nationalities: B02 选中的 ISO 国家码（`prefer_not` 视为空集）
    ///   - courseStage: B03 选中的课程阶段码
    ///   - consentGranted: 是否**当前**持有有效研究同意
    ///   - priorUse: 新旧用户判定（仅 `new` 可纳入）
    static func evaluate(isAdult: Bool?,
                         nationalities: Set<String>?,
                         courseStage: String?,
                         consentGranted: Bool,
                         priorUse: PriorUse) -> Outcome {
        // 同意是前提：未同意不进入研究库，但这不是「不合格」，
        // 而是根本不产生参与者记录（字典 §5：拒绝时不必创建参与者）。
        guard consentGranted else { return .pending }

        // 背景表未答完 → pending，等答完再判，不猜测
        guard let isAdult, let nationalities, let courseStage else { return .pending }

        guard isAdult else { return .excluded(.age) }
        guard !nationalities.isDisjoint(with: requiredNationalities) else {
            return .excluded(.nationality)
        }
        guard allowedCourseStages.contains(courseStage) else {
            return .excluded(.courseStage)
        }
        // 本轮仅纳入新用户
        guard priorUse.status == .new else { return .excluded(.duplicate) }
        return .eligible
    }
}

/// 新旧用户判定（字典 §4 `prior_use_status` / `prior_use_evidence`）。
///
/// 字典指出「新版首次登录、重装或新建账号**不能单独证明**从未使用过旧版」。
/// 本工程可以做得比这更好，但**只在一个方向上**：
/// 旧版学生注册强制 Sign in with Apple 且无游客练习路径，
/// 故 Apple ID 命中旧 `users` 表即可确证为旧用户（`verified_account_history`）。
///
/// **反向不成立**：查不到只说明「无证据表明用过」。换过 Apple 账号、
/// 或旧版下载了但没完成注册的人会看起来像新用户，这类只能记 `insufficient`，
/// 不得据此声称已核实为新用户。
nonisolated struct PriorUse: Equatable {
    enum Status: String { case new, returning, unknown }
    enum Evidence: String {
        case verifiedAccountHistory = "verified_account_history"
        case selfReport = "self_report"
        case combined
        case insufficient
    }

    let status: Status
    let evidence: Evidence

    /// 服务端按 Apple ID 查旧库后返回的判定。
    /// - Parameter foundInLegacy: Apple ID 是否命中旧 `users` 表
    static func fromLegacyLookup(foundInLegacy: Bool) -> PriorUse {
        foundInLegacy
            ? PriorUse(status: .returning, evidence: .verifiedAccountHistory)
            : PriorUse(status: .new, evidence: .insufficient)
    }

    /// 查询失败（离线等）时的安全默认：不推定为新用户。
    static let unknown = PriorUse(status: .unknown, evidence: .insufficient)
}
