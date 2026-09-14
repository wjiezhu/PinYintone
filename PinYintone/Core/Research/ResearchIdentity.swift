import Combine
import Foundation

/// 本机持有的研究身份：研究编号 + 所用配置。
///
/// `participantID` **由服务端随机生成**，不是 Apple 标识或设备号的派生值
/// （字典 §4：「不得直接使用 Apple 标识作研究编号」）。
/// 本地只缓存服务端发回的编号，换设备或重装后由服务端按业务账号键
/// 幂等地返回**同一个**编号，不会产生第二份。
@MainActor
final class ResearchIdentity: ObservableObject {
    static let shared = ResearchIdentity()

    private enum Key {
        static let participant = "pt_research_participant_id"
        static let manifest = "pt_research_manifest_id"
        static let study = "pt_research_study_id"
    }

    @Published private(set) var participantID: String?
    @Published private(set) var manifestID: String?
    private(set) var studyID: String?

    private init() {
        let d = UserDefaults.standard
        participantID = d.string(forKey: Key.participant)
        manifestID = d.string(forKey: Key.manifest)
        studyID = d.string(forKey: Key.study)
    }

    var isEnrolled: Bool { participantID != nil && manifestID != nil }

    func store(participantID: String, manifestID: String, studyID: String) {
        let d = UserDefaults.standard
        d.set(participantID, forKey: Key.participant)
        d.set(manifestID, forKey: Key.manifest)
        d.set(studyID, forKey: Key.study)
        self.participantID = participantID
        self.manifestID = manifestID
        self.studyID = studyID
    }

    /// 撤回同意时清除本地身份。
    /// 注意：**服务端的参与者记录与既有资料不因此删除**——撤回只停止后续采集，
    /// 退出前资料的处理按知情说明执行（字典 §5），不是账号注销。
    func clearOnWithdrawal() {
        let d = UserDefaults.standard
        [Key.participant, Key.manifest, Key.study].forEach { d.removeObject(forKey: $0) }
        participantID = nil
        manifestID = nil
        studyID = nil
    }
}
