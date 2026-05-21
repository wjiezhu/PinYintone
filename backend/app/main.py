from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .database import Base, engine
from .routers import auth, sync, teacher

# 开发期自动建表（生产建议改用 Alembic 迁移）
Base.metadata.create_all(bind=engine)

app = FastAPI(title="Pinyintone Backend", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(sync.router)
app.include_router(teacher.router)


@app.get("/health")
def health():
    return {"status": "ok"}
