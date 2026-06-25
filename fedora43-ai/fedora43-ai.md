fedora43-ai variable SOT

format:
  FILE VARIABLE TYPE FLAGS

files:
  config = config.conf_example
  env = env.example
  container = container.example

rules:
  numbering is global in setup.sh repo order
  duplicate variables keep their first number
  flags are written right of TYPE
  required means config.sh must not skip the value
  default-preset=value means prefilled but still explicit
  autofill=blank-if:CONTROL=value means config.sh writes blank without asking
  sqlite state lives in STATE and gets an automatic repo bind mount

repo order:
  CODEANALYST
  JUGO
  CITADEL
  VikAI
  PV_D-A-CH
  KIWIX_BRIDGE
  NAPOLEON_HILLS_AI_MASTERMIND_CLASSES
  SOLANA_AIRGAPPED_DEBIAN_WORKFLOW
  NaturalGrounding-Tiktok-Ying-Video-Manager
  DAILYNEWS
  CALENDAR
  ZEROINBOX
  KACHELMANN
  SPANKER

example:
  config FASTAPI_HOST string required
  config REPO_PORT integer required
  env REPO_DB_BACKEND enum required
  env REPO_DB_HOST string required autofill=blank-if:REPO_DB_BACKEND=sqlite
  env REPO_DB_PORT integer required autofill=blank-if:REPO_DB_BACKEND=sqlite
  env REPO_DB_NAME string required autofill=blank-if:REPO_DB_BACKEND=sqlite
  env REPO_DB_USER string required autofill=blank-if:REPO_DB_BACKEND=sqlite
  env REPO_DB_PW secret required autofill=blank-if:REPO_DB_BACKEND=sqlite
  env REPO_DB_PREFIX string required autofill=blank-if:REPO_DB_BACKEND=sqlite
  container REPO_PUBLISH_PORT integer required
