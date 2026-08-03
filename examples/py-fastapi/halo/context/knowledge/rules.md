# Rules

## Naming Rules

- API JSON fields use camelCase: `setId`, `setName`.
- Python attributes and function names use snake_case: `set_id`, `list_model_sets`.
- Database columns use snake_case: `set_id`, `created_at`.
- Error code constants use UPPER_SNAKE_CASE: `MODEL_SET_NOT_FOUND`.
- URL paths use kebab-case resource nouns: `/api/model-sets`.
- Router prefixes carry the resource; decorators carry only what follows it.
