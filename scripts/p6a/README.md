# P6-A / beta verification tools

Run from the repository root. Set CANTING_P6A_RUN_ID to a new identifier for every evidence round. A directory containing validation.json is frozen.

Run run.py analyze, full, kotlin, universal, split sequentially. Kotlin explicitly clears only its generated test output before running. Do not run Flutter and Gradle concurrently.

The local Android SDK, Flutter and JBR paths follow the established P5 environment. For another host, configure those paths and offline dependency caches first. Ensure android/local.properties version fields match pubspec.yaml; inspect_artifacts.py verifies the actual APK identity against pubspec.yaml.

Both APK forms use force-version-code-ignoring-abi=true. Increment the base versionCode above every previously distributed package. A versionName change alone does not determine Android upgrade eligibility.

Run inspect_artifacts.py with Python and Pillow, then validate_configuration.py. The inspector verifies the legacy beta and P5 artifact identities, the two new APK identities, signatures, ABI sets, lack of network permissions, and all launcher variants using compiled resource mappings and visible RGBA equality. It requires the existing local historical APKs for comparison; these must never be committed to Git.

icons.py regenerates launcher assets from branding/canting-icon-v1.png and saves mask previews. It uses only the repository master, not the original handoff path. Run it before tests/builds, never against frozen evidence.

Logs, commands, timestamps and build source hashes go to dev-docs/p6a-evidence/<run-id>; copied build APKs go to build/p6a-artifacts/<run-id>. User delivery is assembled separately with START-HERE, hashes, identity, feedback and limitations. Do not treat local automated results as device acceptance.
