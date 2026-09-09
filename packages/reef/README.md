# reef

Reef MVVM framework core: ValueListenable-first pages, models and viewmodels.

- **Never Streams** — reactive state is `ValueListenable<T>` everywhere; the universal
  async/error surface is `ValueListenable<Async<Result<E, T>>>`.
- **Page / Model / ViewModel / Provider** quartet — see `docs/blueprint.md`.
- **Model** — immutable, serializable, named transformation methods returning the new
  model or `Result<E, Model>`.
- **ViewModel** — owns the model, exposes `ValueListenable<M>`, mediates every UI↔model
  transition with transient-unsubscription loop-breaking (`bind`).
- **Formularium** integration — field validators delegate to model methods; non-field
  async/error state lives in `Operation`s.

See `docs/blueprint.md` for the full architecture.
