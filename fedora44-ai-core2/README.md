# fedora44-ai-core2

`fedora44-ai-core2` is the private runtime layer between the heavy Fedora core
and the Safrano project layers:

```text
fedora44-ai-core
  -> fedora44-ai-core2
  -> fedora44-ai-base
  -> fedora44-ai-safrano9999
```

The image reuses all operating-system, AI CLI, Hermes, networking, Vditor and
crypto packages from `fedora44-ai-core`. At image build time it copies only the
verified OpenClaw JavaScript distribution, NOTE source and distro-neutral
Python runtime from the public `openclaw-ephemeral` image. NOTE's Python
environment is rebuilt on Fedora.

At every container boot systemd:

1. projects selected persistent paths and named volumes;
2. rebuilds `openclaw.json` completely from injected environment variables;
3. lets a later Safrano layer register only its additional plugins;
4. starts the OpenClaw gateway;
5. rebuilds Hermes `config.yaml` from the same injected OpenAI-v1 provider
   groups before starting Hermes.

OpenClaw and Hermes configuration files are deliberately ephemeral. Targeted
workspace, agent, authentication and state paths can remain persistent.
