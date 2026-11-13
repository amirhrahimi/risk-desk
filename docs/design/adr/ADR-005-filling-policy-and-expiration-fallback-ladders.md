# ADR-005 Filling-policy and expiration fallback ladders

- **Context:** Servers differ in accepted filling policies and expiration types; flags are sometimes misleading.
- **Decision:** Derive candidates from symbol flags, try them in order, fall back only on the specific retcode, cache what worked per symbol and action; provide an override input for diagnostics.
- **Consequences:** Works on unknown brokers without configuration; an extra round trip on the first order of a symbol at worst.
