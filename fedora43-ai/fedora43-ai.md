1. FASTAPI_HOST	required; FastAPI bind host
2. CODEANALYST_PORT	required; CODEANALYST internal port
3. CODEANALYST_PUBLISH_PORT	required; CODEANALYST host port
4. JUGO_PORT	required; JUGO internal port
5. USE_TMUX	required
6. TMUX_SHELL	required
7. JUGO_TMUX_SESSION_PREFIX	required; autofill blank if USE_TMUX=false
8. JUGO_DB_BACKEND	required
9. JUGO_DB_HOST	required; autofill blank if JUGO_DB_BACKEND=sqlite
10. JUGO_DB_PORT	required; autofill blank if JUGO_DB_BACKEND=sqlite
11. JUGO_DB_NAME	required; autofill blank if JUGO_DB_BACKEND=sqlite
12. JUGO_DB_USER	required; autofill blank if JUGO_DB_BACKEND=sqlite
13. JUGO_DB_PW	required; autofill blank if JUGO_DB_BACKEND=sqlite
14. JUGO_DB_PREFIX	required; autofill blank if JUGO_DB_BACKEND=sqlite
15. DEEPL_API_KEY	optional
16. OPENAI_V1_URL	required
17. OPENAI_V1_PORT	required
18. OPENAI_V1_KEY	required
19. JUGO_PUBLISH_PORT	required
20. CITADEL_WEBUI_PORT	required
21. CITADEL_SUBNET_IP	optional
22. CITADEL_TAILSCALE	optional
23. CITADEL_CLOUDFLARE	optional
24. CITADEL_CLOUDFLARE_DOMAIN	optional
25. CITADEL_CLOUDFLARE_ACCOUNT_ID	optional
26. CITADEL_CLOUDFLARE_ZONE_ID	optional
27. CITADEL_CLOUDFLARE_TUNNEL_ID	optional
28. CITADEL_CLOUDFLARE_ORIGIN_HOST	optional
29. CLOUDFLARE_API_TOKEN	optional
30. CLOUDFLARE_EMAIL	optional
31. TUNNEL_TOKEN	optional
32. CITADEL_WEBUI_PUBLISH_PORT	required
33. VIKUNJA_HOST	required
34. VIKUNJA_CONTAINER	required
35. ASSIGNEE_USERNAME	required; default preset vikai
36. TRANSPORT	required; default preset cli
37. TARGET	required; default preset openclaw-tui
38. VIKAI_OPENCLAW_LLM	required; default preset gemini/gemini-3.5-flash
39. VIKAI_HERMES_LLM	required; default preset gemini/gemini-3.5-flash
40. TOKEN_WORKER	required; default preset worker
41. TOKEN_ARCHITECT	required; default preset architect
42. TOKEN_QC	required; default preset qc
43. PV_DACH_PORT	required
44. PV_DACH_OPENAI_V1_MODEL	required; default model
45. PV_DACH_QGIS_WEBHOOK_SERVER_ON	optional
46. PV_DACH_QGIS_WEBHOOK_SERVER_PORT	required when webhook server is on
47. PV_DACH_QGIS_WEBHOOK_CLIENT_URL	optional
48. PV_DACH_DB_BACKEND	required
49. PV_DACH_DB_HOST	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
50. PV_DACH_DB_PORT	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
51. PV_DACH_DB_NAME	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
52. PV_DACH_DB_USER	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
53. PV_DACH_DB_PW	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
54. PV_DACH_DB_PREFIX	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
55. TS_AUTHKEY	required
56. PV_DACH_QGIS_WEBHOOK_SERVER_TOKEN	required
57. PV_DACH_QGIS_WEBHOOK_CLIENT_TOKEN	required
58. PV_DACH_PUBLISH_PORT	required
59. PV_DACH_QGIS_WEBHOOK_SERVER_PUBLISH_PORT	required
60. KIWIX_BRIDGE_PORT	required
61. KIWIX_URL	required
62. KIWIX_BRIDGE_PUBLISH_PORT	required
63. NAPOLEON_PORT	required
64. NAPOLEON_OPENAI_V1_DEFAULT_LLM	required; default preset gemini/gemini-3.5-flash
65. NAPOLEON_DB_BACKEND	required
66. NAPOLEON_DB_HOST	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
67. NAPOLEON_DB_PORT	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
68. NAPOLEON_DB_NAME	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
69. NAPOLEON_DB_USER	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
70. NAPOLEON_DB_PW	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
71. NAPOLEON_DB_PREFIX	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
72. NAPOLEON_PUBLISH_PORT	required
