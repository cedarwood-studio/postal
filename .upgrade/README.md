# .upgrade

Files the upgrade process added. Nothing here ships with the application.

- `baseline/examples.json`: every test example and its status before the upgrade began.
- `baseline/parity.json`: the application's recorded responses to the requests in `parity-inputs.json`, before the upgrade began.
- `baseline/parity-noise-mask.json`: fields that differed between two recordings of the same code, ignored in comparisons.
- `accepted-differences.json`: behavior differences a stage declared, each with its reason. Empty means none.
- `parity_record.rb`, `parity.py`, `check.py`: the recorder and the comparison CI runs.

The rule each stage is held to: no example that passed at the baseline fails or disappears, and no recorded response changes without an entry in `accepted-differences.json`.
