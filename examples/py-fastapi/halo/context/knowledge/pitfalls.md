# Pitfalls

| Pitfall | Trigger | Guidance | Source |
|---------|---------|----------|--------|
| Collection root reads as unregistered | The route is `@router.get("")` and the prefix carries the path | The full URL is `prefix + path`; an empty decorator path is a route, not a missing one | sample |
| Prefix invisible to a line-based reader | `APIRouter(...)` is spread over several lines | Route tooling must read the whole call, not one line | sample |
| Naming drift | API JSON, Python attributes, and DB columns use different styles | Keep the naming rules in `rules.md` | sample |
