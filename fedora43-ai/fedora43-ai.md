https://github.com/safrano9999/CODEANALYST
#env_example
#config.conf_example
1. FASTAPI_HOST	required; FastAPI bind host
2. CODEANALYST_PORT	required
#container_example
3. CODEANALYST_PUBLISH_PORT	required

https://github.com/safrano9999/JUGO
#env_example
8. JUGO_DB_BACKEND	required
9. JUGO_DB_HOST	required; autofill blank if JUGO_DB_BACKEND=sqlite
10. JUGO_DB_PORT	required
11. JUGO_DB_NAME	required; autofill blank if JUGO_DB_BACKEND=sqlite
12. JUGO_DB_USER	required; autofill blank if JUGO_DB_BACKEND=sqlite
13. JUGO_DB_PW	required; autofill blank if JUGO_DB_BACKEND=sqlite
14. JUGO_DB_PREFIX	required; autofill blank if JUGO_DB_BACKEND=sqlite
15. DEEPL_API_KEY	optional
16. OPENAI_V1_URL	required
17. OPENAI_V1_PORT	required
18. OPENAI_V1_KEY	required
#config.conf_example
4. JUGO_PORT	required
5. USE_TMUX	required
6. TMUX_SHELL	required
7. JUGO_TMUX_SESSION_PREFIX	required; autofill blank if USE_TMUX=false
#container_example
19. JUGO_PUBLISH_PORT	required

https://github.com/safrano9999/CITADEL
#env_example
29. CLOUDFLARE_API_TOKEN	optional
30. CLOUDFLARE_EMAIL	optional
31. TUNNEL_TOKEN	optional
#config.conf_example
20. CITADEL_WEBUI_PORT	required
21. CITADEL_SUBNET_IP	optional
22. CITADEL_TAILSCALE	optional
23. CITADEL_CLOUDFLARE	optional
24. CITADEL_CLOUDFLARE_DOMAIN	optional
25. CITADEL_CLOUDFLARE_ACCOUNT_ID	optional
26. CITADEL_CLOUDFLARE_ZONE_ID	optional
27. CITADEL_CLOUDFLARE_TUNNEL_ID	optional
28. CITADEL_CLOUDFLARE_ORIGIN_HOST	optional
#container_example
32. CITADEL_WEBUI_PUBLISH_PORT	required

https://github.com/safrano9999/VikAI
#env_example
40. TOKEN_WORKER	required; default preset worker
41. TOKEN_ARCHITECT	required; default preset architect
42. TOKEN_QC	required; default preset qc
#config.conf_example
33. VIKUNJA_HOST	required
34. VIKUNJA_CONTAINER	required
35. ASSIGNEE_USERNAME	required; default preset vikai
36. TRANSPORT	required; default preset cli
37. TARGET	required; default preset openclaw-tui
38. VIKAI_OPENCLAW_LLM	required; default preset gemini/gemini-3.5-flash
39. VIKAI_HERMES_LLM	required; default preset gemini/gemini-3.5-flash
#container_example

https://github.com/safrano9999/PV_D-A-CH
#env_example
48. PV_DACH_DB_BACKEND	required
49. PV_DACH_DB_HOST	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
50. PV_DACH_DB_PORT	required
51. PV_DACH_DB_NAME	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
52. PV_DACH_DB_USER	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
53. PV_DACH_DB_PW	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
54. PV_DACH_DB_PREFIX	required; autofill blank if PV_DACH_DB_BACKEND=sqlite
55. TS_AUTHKEY	required
56. PV_DACH_QGIS_WEBHOOK_SERVER_TOKEN	required
57. PV_DACH_QGIS_WEBHOOK_CLIENT_TOKEN	required
#config.conf_example
43. PV_DACH_PORT	required
44. PV_DACH_OPENAI_V1_MODEL	required; default model
45. PV_DACH_QGIS_WEBHOOK_SERVER_ON	optional
46. PV_DACH_QGIS_WEBHOOK_SERVER_PORT	required
47. PV_DACH_QGIS_WEBHOOK_CLIENT_URL	optional
#container_example
58. PV_DACH_PUBLISH_PORT	required
59. PV_DACH_QGIS_WEBHOOK_SERVER_PUBLISH_PORT	required

https://github.com/safrano9999/KIWIX_BRIDGE
#env_example
#config.conf_example
60. KIWIX_BRIDGE_PORT	required
61. KIWIX_URL	required
#container_example
62. KIWIX_BRIDGE_PUBLISH_PORT	required

https://github.com/safrano9999/NAPOLEON_HILLS_AI_MASTERMIND_CLASSES
#env_example
65. NAPOLEON_DB_BACKEND	required
66. NAPOLEON_DB_HOST	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
67. NAPOLEON_DB_PORT	required
68. NAPOLEON_DB_NAME	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
69. NAPOLEON_DB_USER	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
70. NAPOLEON_DB_PW	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
71. NAPOLEON_DB_PREFIX	required; autofill blank if NAPOLEON_DB_BACKEND=sqlite
#config.conf_example
63. NAPOLEON_PORT	required
64. NAPOLEON_OPENAI_V1_DEFAULT_LLM	required; default preset gemini/gemini-3.5-flash
#container_example
72. NAPOLEON_PUBLISH_PORT	required

https://github.com/safrano9999/SOLANA_AIRGAPPED_DEBIAN_WORKFLOW
#env_example
#config.conf_example
#container_example

https://github.com/safrano9999/NaturalGrounding-Tiktok-Ying-Video-Manager
#env_example
75. NATURALGROUNDING_DB_BACKEND	required
76. NATURALGROUNDING_DB_PREFIX	required; autofill blank if NATURALGROUNDING_DB_BACKEND=sqlite
77. NATURALGROUNDING_DB_NAME	required; autofill blank if NATURALGROUNDING_DB_BACKEND=sqlite
78. NATURALGROUNDING_DB_USER	required; autofill blank if NATURALGROUNDING_DB_BACKEND=sqlite
79. NATURALGROUNDING_DB_PW	required; autofill blank if NATURALGROUNDING_DB_BACKEND=sqlite
80. NATURALGROUNDING_DB_URL	required; autofill blank if NATURALGROUNDING_DB_BACKEND=sqlite
81. NATURALGROUNDING_DB_PORT	required; autofill blank if NATURALGROUNDING_DB_BACKEND=sqlite
82. NATURALGROUNDING_DJANGO_SECRET_KEY	
83. NATURALGROUNDING_ADMIN_EMAIL	
84. NATURALGROUNDING_ADMIN_PASSWORD	
#config.conf_example
73. NATURALGROUNDING_PORT	required
74. NATURALGROUNDING_VIDEOS_DIR	
#container_example
85. NATURALGROUNDING_PUBLISH_PORT	required

https://github.com/safrano9999/DAILYNEWS
#env_example
#config.conf_example
#container_example

https://github.com/safrano9999/CALENDAR
#env_example
86. CALENDAR_URL	
87. CALENDAR_USER	
88. CALENDAR_PASSWORD	
#config.conf_example
#container_example

https://github.com/safrano9999/ZEROINBOX
#env_example
89. ZEROINBOX_PROVIDER	
90. ZEROINBOX_EMAIL	
91. ZEROINBOX_APP_PASSWORD	
92. ZEROINBOX_MODEL	
#config.conf_example
#container_example

https://github.com/safrano9999/KACHELMANN
#env_example
94. KACHELMANN_DB_BACKEND	
95. KACHELMANN_DB_URL	
96. KACHELMANN_DB_PORT	required
97. KACHELMANN_DB_NAME	
98. KACHELMANN_DB_USER	
99. KACHELMANN_DB_PW	
100. KACHELMANN_DB_PREFIX	
101. KACHELMANN_EDITOR_TOKEN	
#config.conf_example
93. KACHELMANN_PORT	required
#container_example
102. KACHELMANN_PUBLISH_PORT	required

https://github.com/safrano9999/SPANKER
#env_example
104. SPANKER_DB_BACKEND	
105. SPANKER_DB_NAME	
106. SPANKER_DB_USER	
107. SPANKER_DB_PW	
108. SPANKER_DB_URL	
109. SPANKER_DB_PORT	required
110. SPANKER_DB_PREFIX	
#config.conf_example
103. SPANKER_PORT	required
#container_example
111. SPANKER_PUBLISH_PORT	required
