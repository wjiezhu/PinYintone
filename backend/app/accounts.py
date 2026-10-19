"""业务账号的稳定内部编号。

登录身份 = (登录方式, 该方式下的用户号)，即 `users.auth_provider / auth_subject`：
apple → Sign in with Apple 的用户号，google → Google 的 sub。用户号取自服务端
验过签的凭证（identity.py）。

`users` 表按 device_id 建行：同一个账号在两台设备上是两行，
同一台设备换一个账号登录则是**同一行被改写**。研究纳入必须按「账号」去重
（需求 R08、验收 A20），两种情况都要对：

- 同一账号换设备 → 还是同一位参与者；
- 同一台设备换账号 → 是另一位参与者，看不到上一个人的任何研究状态；
- 上一个人再登录回来 → 还是他原来那位参与者。

所以编号挂在登录身份上（`account_identities`），设备行上的 `account_id` 只是它的副本。
同一个人用 Apple 和 Google 各登录一次，是两个账号——两种登录方式之间没有可验证的关联。

`account_id` 是服务端随机生成的，**不是**用户号的派生值——
研究侧的 research_identity_map 存它，不存用户号。
"""
import uuid

from . import models


def identity_of(user: models.User) -> tuple[str, str] | None:
    if user.auth_provider and user.auth_subject:
        return (user.auth_provider, user.auth_subject)
    return None


def users_with_identity(db, provider: str, subject: str) -> list[models.User]:
    return (db.query(models.User)
            .filter(models.User.auth_provider == provider,
                    models.User.auth_subject == subject).all())


def sibling_users(db, user: models.User) -> list[models.User]:
    """与该设备行属于同一业务账号的全部设备行（含自己）。"""
    ident = identity_of(user)
    if ident is None:
        return [user]
    rows = users_with_identity(db, *ident)
    return rows if any(r.device_id == user.device_id for r in rows) else rows + [user]


def forget_previous_owner(user: models.User, provider: str, subject: str) -> None:
    """设备行即将换成另一个登录身份：清掉上一位使用者留下的编号与验证状态。

    必须在改写 `auth_provider / auth_subject` **之前**调用。不清的话，新账号会沿用旧编号，
    在研究里与上一个人合并成同一位参与者。换登录方式（Apple → Google）也算换人。
    """
    ident = identity_of(user)
    if ident is not None and ident != (provider, subject):
        user.account_id = None
        user.auth_verified_at = None


def ensure_account_id(db, user: models.User) -> str:
    """返回该账号的稳定编号；没有就生成，并写回同账号的全部设备行。

    调用方负责 commit。
    """
    ident = identity_of(user)
    if ident is None:
        # 没有登录身份的旧式档案：只能以设备为单位
        if not user.account_id:
            user.account_id = str(uuid.uuid4())
        return user.account_id

    siblings = sibling_users(db, user)
    link = db.get(models.AccountLink, ident)
    if link is None:
        # 本表出现之前，编号只写在设备行上：同一身份的行上若已有，就沿用
        existing = next((s.account_id for s in siblings if s.account_id), None)
        link = models.AccountLink(provider=ident[0], subject=ident[1],
                                  account_id=existing or str(uuid.uuid4()))
        db.add(link)
    for s in siblings:
        if s.account_id != link.account_id:
            s.account_id = link.account_id
    return link.account_id
