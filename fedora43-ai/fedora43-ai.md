1. FASTAPI_HOST	required; FastAPI bind host
2. CODEANALYST_PORT	required; CODEANALYST internal port
3. CODEANALYST_PUBLISH_PORT	required; CODEANALYST host port
4. JUGO_PORT	required; JUGO internal port
5. USE_TMUX	required; enables tmux integration
6. TMUX_SHELL	required; shell used for tmux sessions
7. JUGO_TMUX_SESSION_PREFIX	required; autofill blank if USE_TMUX=false
8. JUGO_DB_BACKEND	required; sqlite/postgres/mysql/mariadb
9. JUGO_DB_HOST	required; autofill blank if JUGO_DB_BACKEND=sqlite
10. JUGO_DB_PORT	required; autofill blank if JUGO_DB_BACKEND=sqlite
11. JUGO_DB_NAME	required; autofill blank if JUGO_DB_BACKEND=sqlite
12. JUGO_DB_USER	required; autofill blank if JUGO_DB_BACKEND=sqlite
13. JUGO_DB_PW	required; autofill blank if JUGO_DB_BACKEND=sqlite
14. JUGO_DB_PREFIX	required; autofill blank if JUGO_DB_BACKEND=sqlite
15. DEEPL_API_KEY	optional; DeepL key
16. OPENAI_V1_URL	required; OpenAI-compatible v1 base URL
17. OPENAI_V1_PORT	required; OpenAI-compatible v1 port
18. OPENAI_V1_KEY	required; OpenAI-compatible v1 bearer/key
19. JUGO_PUBLISH_PORT	required; JUGO host port
20. CITADEL_WEBUI_PORT	required; CITADEL internal port
21. CITADEL_SUBNET_IP	optional; preset later from host subnet
22. CITADEL_TAILSCALE	optional; map Tailscale routes when enabled
23. CITADEL_CLOUDFLARE	optional; map Cloudflare routes when enabled
24. CITADEL_CLOUDFLARE_DOMAIN	optional; Cloudflare route domain
25. CITADEL_CLOUDFLARE_ACCOUNT_ID	optional; Cloudflare account id
26. CITADEL_CLOUDFLARE_ZONE_ID	optional; Cloudflare zone id
27. CITADEL_CLOUDFLARE_TUNNEL_ID	optional; Cloudflare tunnel id
28. CITADEL_CLOUDFLARE_ORIGIN_HOST	optional; origin host for tunnel ingress
29. CLOUDFLARE_API_TOKEN	optional; Cloudflare API token
30. CLOUDFLARE_EMAIL	optional; default Cloudflare Access email
31. TUNNEL_TOKEN	optional; cloudflared tunnel token
32. CITADEL_WEBUI_PUBLISH_PORT	required; CITADEL host port
33. VIKUNJA_HOST	required; Vikunja host
34. VIKUNJA_CONTAINER	required; Vikunja container name
35. ASSIGNEE_USERNAME	required; default preset vikai
36. TRANSPORT	required; default preset cli
37. TARGET	required; default preset openclaw-tui
38. VIKAI_OPENCLAW_LLM	required; default preset gemini/gemini-3.5-flash
39. VIKAI_HERMES_LLM	required; default preset gemini/gemini-3.5-flash
40. TOKEN_WORKER	required; default preset worker
41. TOKEN_ARCHITECT	required; default preset architect
42. TOKEN_QC	required; default preset qc
43. PV_DACH_PORT	required; PV_D-A-CH internal port
44. PV_DACH_OPENAI_V1_MODEL	required; default vision/model choice
45. PV_DACH_QGIS_WEBHOOK_SERVER_ON	optional; start QGIS webhook server
46. PV_DACH_QGIS_WEBHOOK_SERVER_PORT	required when webhook server is on
47. PV_DACH_QGIS_WEBHOOK_CLIENT_URL	optional; remote QGIS webhook URL
48. PV_DACH_DB_BACKEND	required; sqlite/postgres/mysql/mariadb
49. PV_DACH_DB_HOST	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
50. PV_DACH_DB_PORT	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
51. PV_DACH_DB_NAME	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
52. PV_DACH_DB_USER	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
53. PV_DACH_DB_PW	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
54. PV_DACH_DB_PREFIX	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
55. TS_AUTHKEY	required; Tailscale auth key for QGIS container
56. PV_DACH_QGIS_WEBHOOK_SERVER_TOKEN	required; QGIS webhook server bearer
57. PV_DACH_QGIS_WEBHOOK_CLIENT_TOKEN	required; QGIS webhook client bearer
58. PV_DACH_PUBLISH_PORT	required; PV_D-A-CH host port
59. PV_DACH_QGIS_WEBHOOK_SERVER_PUBLISH_PORT	required; QGIS webhook host port
60. KIWIX_BRIDGE_PORT	required; KIWIX_BRIDGE internal port
61. KIWIX_URL	required; Kiwix server URL
62. KIWIX_BRIDGE_PUBLISH_PORT	required; KIWIX_BRIDGE host port
63. NAPOLEON_PORT	required; Napoleon internal port
64. NAPOLEON_OPENAI_V1_DEFAULT_LLM	required; default preset gemini/gemini-3.5-flash
65. NAPOLEON_DB_BACKEND	required; sqlite/postgres/mysql/mariadb
66. NAPOLEON_DB_HOST	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
67. NAPOLEON_DB_PORT	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
68. NAPOLEON_DB_NAME	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
69. NAPOLEON_DB_USER	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
70. NAPOLEON_DB_PW	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
71. NAPOLEON_DB_PREFIX	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
72. NAPOLEON_PUBLISH_PORT	required; Napoleon host port
73. NATURALGROUNDING_PORT	required; NaturalGrounding internal port
74. NATURALGROUNDING_VIDEOS_DIR	required; video directory mount source
75. NATURALGROUNDING_DB_BACKEND	required; sqlite/postgres/mysql/mariadb
76. NATURALGROUNDING_DB_PREFIX	required; autofill blank if NATURALGROUNDING_DB_BACKEND=sqlite
77. NATURALGROUNDING_DB_NAME	required; autofill blank if NATURALGROUNDING_DB_BACKEND=sqlite
78. NATURALGROUNDING_DB_USER	required; autofill blank if NATURALGROUNDING_DB_BACKEND=sqlite
79. NATURALGROUNDING_DB_PW	required; autofill blank if NATURALGROUNDING_DB_BACKEND=sqlite
80. NATURALGROUNDING_DB_URL	required; autofill blank if NATURALGROUNDING_DB_BACKEND=sqlite
81. NATURALGROUNDING_DB_PORT	required; autofill blank if NATURALGROUNDING_DB_BACKEND=sqlite
82. NATURALGROUNDING_DJANGO_SECRET_KEY	required
83. NATURALGROUNDING_ADMIN_EMAIL	required
84. NATURALGROUNDING_ADMIN_PASSWORD	required
85. NATURALGROUNDING_PUBLISH_PORT	required; NaturalGrounding host port
86. CALENDAR_URL	required; CalDAV principal URL
87. CALENDAR_USER	required; calendar user
88. CALENDAR_PASSWORD	required; calendar password
89. ZEROINBOX_PROVIDER	required; mail provider
90. ZEROINBOX_EMAIL	required; mail account
91. ZEROINBOX_APP_PASSWORD	required; mail app password
92. ZEROINBOX_MODEL	required; classification model
93. KACHELMANN_PORT	required; KACHELMANN internal port
94. KACHELMANN_DB_BACKEND	required; sqlite/postgres/mysql/mariadb
95. KACHELMANN_DB_URL	required; autofill blank if KACHELMANN_DB_BACKEND=sqlite
96. KACHELMANN_DB_PORT	required; autofill blank if KACHELMANN_DB_BACKEND=sqlite
97. KACHELMANN_DB_NAME	required; autofill blank if KACHELMANN_DB_BACKEND=sqlite
98. KACHELMANN_DB_USER	required; autofill blank if KACHELMANN_DB_BACKEND=sqlite
99. KACHELMANN_DB_PW	required; autofill blank if KACHELMANN_DB_BACKEND=sqlite
100. KACHELMANN_DB_PREFIX	required; autofill blank if KACHELMANN_DB_BACKEND=sqlite
101. KACHELMANN_EDITOR_TOKEN	required; editor token
102. KACHELMANN_PUBLISH_PORT	required; KACHELMANN host port
103. SPANKER_PORT	required; SPANKER internal port
104. SPANKER_DB_BACKEND	required; sqlite/postgres/mysql/mariadb
105. SPANKER_DB_NAME	required; autofill blank if SPANKER_DB_BACKEND=sqlite
106. SPANKER_DB_USER	required; autofill blank if SPANKER_DB_BACKEND=sqlite
107. SPANKER_DB_PW	required; autofill blank if SPANKER_DB_BACKEND=sqlite
108. SPANKER_DB_URL	required; autofill blank if SPANKER_DB_BACKEND=sqlite
109. SPANKER_DB_PORT	required; autofill blank if SPANKER_DB_BACKEND=sqlite
110. SPANKER_DB_PREFIX	required; autofill blank if SPANKER_DB_BACKEND=sqlite
111. SPANKER_PUBLISH_PORT	required; SPANKER host port
