"""业务账号的稳定内部编号。

`users` 表按 device_id 建行：同一个 Apple 账号在两台设备上是两行。
研究纳入如果按 device_id 去重，同一个人换设备就会变成第二位参与者
（需求 R08、验收 A20）。这里给同一 Apple 账号的所有设备行分配同一个
随机 `account_id`，纳入按它去重。

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


def ensure_account_id(db, user: models.User) -> str:
    """返回该账号的稳定编号；没有就生成，并写回同账号的全部设备行。

    调用方负责 commit。
    """
    siblings = sibling_users(db, user)
    existing = next((s.account_id for s in siblings if s.account_id), None)
    account_id = existing or str(uuid.uuid4())
    for s in siblings:
        if s.account_id != account_id:
            s.account_id = account_id
    return account_id
