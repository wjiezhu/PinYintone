"""业务账号的稳定内部编号。

`users` 表按 device_id 建行：同一个 Apple 账号在两台设备上是两行，
同一台设备换一个 Apple 账号登录则是**同一行被改写**。研究纳入必须按「账号」去重
（需求 R08、验收 A20），两种情况都要对：

- 同一账号换设备 → 还是同一位参与者；
- 同一台设备换账号 → 是另一位参与者，看不到上一个人的任何研究状态；
- 上一个人再登录回来 → 还是他原来那位参与者。

所以编号挂在 Apple 账号上（`account_links`），设备行上的 `account_id` 只是它的副本。

`account_id` 是服务端随机生成的，**不是** Apple 标识的派生值——
研究侧的 research_identity_map 存它，不存 Apple 标识。
"""
import uuid

from . import models


def sibling_users(db, user: models.User) -> list[models.User]:
    """与该设备行属于同一业务账号的全部设备行（含自己）。"""
    if not user.apple_user_id:
        return [user]
    rows = (db.query(models.User)
            .filter(models.User.apple_user_id == user.apple_user_id).all())
    return rows if any(r.device_id == user.device_id for r in rows) else rows + [user]


def forget_previous_owner(user: models.User, new_apple_user_id: str | None) -> None:
    """设备行即将换成另一个 Apple 账号：清掉上一位使用者留下的编号。

    必须在改写 `apple_user_id` **之前**调用。不清的话，新账号会沿用旧编号，
    在研究里与上一个人合并成同一位参与者。
    """
    if new_apple_user_id and user.apple_user_id and user.apple_user_id != new_apple_user_id:
        user.account_id = None


def ensure_account_id(db, user: models.User) -> str:
    """返回该账号的稳定编号；没有就生成，并写回同账号的全部设备行。

    调用方负责 commit。
    """
    if not user.apple_user_id:
        # 没有 Apple 账号的旧式档案：只能以设备为单位
        if not user.account_id:
            user.account_id = str(uuid.uuid4())
        return user.account_id

    siblings = sibling_users(db, user)
    link = db.get(models.AccountLink, user.apple_user_id)
    if link is None:
        # 本表出现之前，编号只写在设备行上：同一 Apple 账号的行上若已有，就沿用
        existing = next((s.account_id for s in siblings if s.account_id), None)
        link = models.AccountLink(apple_user_id=user.apple_user_id,
                                  account_id=existing or str(uuid.uuid4()))
        db.add(link)
    for s in siblings:
        if s.account_id != link.account_id:
            s.account_id = link.account_id
    return link.account_id
