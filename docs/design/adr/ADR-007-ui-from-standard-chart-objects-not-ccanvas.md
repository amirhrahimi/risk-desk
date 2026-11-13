# ADR-007 UI from standard chart objects, not CCanvas

- **Context:** Canvas gives prettier graphics but needs bitmap resources, manual hit-testing and more CPU, and behaves differently across platforms.
- **Decision:** `OBJ_RECTANGLE_LABEL`, `OBJ_BUTTON`, `OBJ_EDIT`, `OBJ_LABEL`, `OBJ_HLINE`, `OBJ_TEXT`.
- **Consequences:** Native click/edit handling, identical on MT4/MT5, simple DPI scaling; limited styling (no rounded corners/gradients).
