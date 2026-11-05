# Architecture Review Checklist

- Does this change improve or preserve locality of behavior?
- Is the code grouped by user flow or use case rather than by technical concern?
- Did we keep related UI, state, and behavior close together?
- Was a new abstraction introduced because it represents a real feature boundary rather than generic reuse pressure?
- Should this code remain feature-local instead of moving to `Shared/`?
- Did we avoid creating or expanding vague buckets such as `Services`, `Managers`, `Helpers`, or `Utilities`?
- If a large file was touched, did we consider extracting one or more small named collaborators instead of extending the file?
- Are the names concrete and role-based, such as `Workflow`, `Coordinator`, `Navigator`, `Store`, `Factory`, `Resolver`, `Builder`, or `Runner`?
- If code was promoted upward, does at least one other distinct flow clearly need it?
- Does the resulting structure make the feature easier to understand by reading a small nearby cluster of files?

## Security

- Does this make anything reachable without authentication?
- Could a secret end up in a log, an API response, an error message or a plaintext file?
- Is every change made through the API recorded in the audit log?
- Does a new action that deletes backups, sends a secret somewhere new, or gives a device access require the `.userPresence` key?
- Is it still safe if Hive's port is open to the internet?
- Does it add any bypass, even one meant only for testing or Debug builds?
