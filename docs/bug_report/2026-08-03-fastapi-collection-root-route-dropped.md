drift-check.sh:305 的 [[ "$path" == /* ]] || continue 丢弃 FastAPI
  集合根路径。APIRouter(prefix="/model-sets") + @router.get("") 是 FastAPI 标准写法，提取出的 path
  为空串，整条注册消失、prefix 也不再拼接：

  ❌ 丢弃  POST   path=[]  ← @router.post("")
  ❌ 丢弃  GET    path=[]  ← @router.get("")
  ✅ 保留  GET    path=[/{set_id}]  → GET /model-sets/{set_id}
