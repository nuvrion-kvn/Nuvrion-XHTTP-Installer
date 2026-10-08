# Product image processing

All selected product packshots have real alpha backgrounds and normal CSS blending. Official transparent manufacturer originals are preferred. Images are locally served as WebP; original downloads and generated PNGs are excluded from the deployment. Lifestyle photos retain cover framing.

Background-extraction prompt set: isolate the exact product, remove only the surrounding white backdrop, floor, halos and detached promotional elements; preserve silhouette, packaging colors, logos and all existing label lettering; preserve white areas inside labels; use genuine transparent alpha, no new shadow, pedestal or objects. One built-in image_gen call per asset. Main product names and varieties were visually checked. Generative extraction can reconstruct tiny label lettering; catalog facts continue to use manufacturer records.

The read-only check `python scripts/check-assets.py` verifies all96 assets,13 lifestyle photos and83 transparent packshots. Its three light-perimeter warnings (Ora et Labora Blanche, Kirin, Einstok) were manually checked on beige: the white pixels belong to labels or metal at the image edge.

| Beer ID | Selected asset | Method | Image source |
|---|---|---|---|
| ru-zhiguli | `/assets/beer-rus-zhiguli-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2026-08-07_12-53-33__da50524e-9245-11f1-a019-7adc2c4a466d.jpg |
| ru-zhiguli1968 | `/assets/beer-rus-zhiguli1968-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2023-02-22_19-20-14__c9b08406-b2cc-11ed-b0a6-525400531e2e.jpg |
| ru-zhiguli-dark | `/assets/beer-rus-zhiguli-dark-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2026-06-19_16-36-19__da6891e8-6be3-11f1-a019-7adc2c4a466d.jpg |
| ru-zhiguli-wheat | `/assets/beer-rus-zhiguli-wheat-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2026-07-13_11-41-43__ad1e8c86-7e96-11f1-a019-7adc2c4a466d.jpg |
| ru-zhiguli-export | `/assets/beer-rus-zhiguli-export-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2025-05-14_17-12-43__80b3de5c-30cd-11f0-bf16-525400531e2e.jpg |
| ru-zhiguli-zero | `/assets/beer-rus-zhiguli-zero-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2026-06-19_16-40-29__6fb39176-6be4-11f1-a019-7adc2c4a466d.jpg |
| ru-zhiguli-mango | `/assets/beer-rus-zhiguli-mango-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2026-06-19_16-40-54__7e800e00-6be4-11f1-a019-7adc2c4a466d.jpg |
| ru-khamovniki-vienna | `/assets/beer-rus-khamovniki-vienna-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2025-06-23_11-47-09__a629b0c0-500e-11f0-a999-525400531e2e.jpg |
| ru-khamovniki-pils | `/assets/beer-rus-khamovniki-pils-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2025-06-23_11-49-07__ec78cfde-500e-11f0-8cb5-525400531e2e.jpg |
| ru-khamovniki-munich | `/assets/beer-rus-khamovniki-munich-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2024-04-11_14-40-42__53c9ba56-f7f8-11ee-b95e-525400531e2e.jpg |
| ru-khamovniki-weiss | `/assets/beer-rus-khamovniki-weiss-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2024-12-03_11-47-14__31cef8c0-b153-11ef-9fbf-525400531e2e.jpg |
| ru-khamovniki-moscow | `/assets/beer-rus-khamovniki-moscow-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2026-05-28_16-16-09__6460e138-5a97-11f1-9e16-aaaa3b88b3e8.jpg |
| ru-trekhgornoe-ale | `/assets/beer-rus-trekhgornoe-ale-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2023-11-09_18-51-46__e34370c8-7f17-11ee-879c-525400531e2e.jpg |
| world-leffe | `/assets/beer-world-leffe-cutout.webp` | Transparent manufacturer original | https://static.wixstatic.com/media/b5a293_8d5893a709a94663a738835dce8e41e0~mv2.png |
| ru-trekhgornoe-blanche | `/assets/beer-rus-trekhgornoe-blanche-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2025-03-25_13-00-39__0146fcb0-0960-11f0-a3ec-525400531e2e.jpg |
| ru-5ocean-ipa | `/assets/beer-rus-5ocean-ipa-cutout.webp` | Background extraction with built-in image_gen | https://mosbrew.ru/media/brand/w458_square/2019-08-16_11-25-15__5f6ed192-bfff-11e9-9dd8-a97d79eb3fbc.jpg |
| world-punk | `/assets/beer-world-punk-cutout.webp` | Background extraction with built-in image_gen | https://cdn.shopify.com/s/files/1/0822/7281/3382/files/Punk_-_PDP_Product_Card.png?v=1787673710 |
| world-extra-schlenkerla | `/assets/beer-world-extra-schlenkerla-cutout.webp` | Background extraction with built-in image_gen | https://shop.schlenkerla.de/media/image/product/3/md/aecht-schlenkerla-rauchbier-maerzen.jpg |
| ru-bakunin-god-hand | `/assets/beer-rus-extra-bakunin-god-hand-cutout.webp` | Background extraction with built-in image_gen | https://static.tildacdn.com/tild3937-6334-4965-b032-366133623135/--mini.png |
| ru-bakunin-moloko | `/assets/beer-rus-extra-bakunin-moloko-cutout.webp` | Transparent manufacturer original | https://drive.google.com/file/d/1A9bSY_u7wHBLbre2t_yO0y7Bdo21ySjg/view |
| ru-bakunin-fibonacci | `/assets/beer-rus-extra-bakunin-fibonacci-cutout.webp` | Transparent manufacturer original | https://static.tildacdn.com/tild3361-6563-4064-b662-306434623866/Fibonacci_05.png |
| ru-bakunin-yunost | `/assets/beer-rus-extra-bakunin-yunost-cutout.webp` | Transparent manufacturer original | https://drive.google.com/file/d/1JJkH8Eh934KiwHoOGw7ln0DwOuDl9w_l/view |
| ru-bakunin-anyweisse | `/assets/beer-rus-extra-bakunin-anyweisse-cutout.webp` | Transparent manufacturer original | https://drive.google.com/file/d/1i3gA87iCcN8qypn1tnvWkq2YFwC_guJo/view |
| ru-bakunin-salty-dog | `/assets/beer-rus-extra-bakunin-salty-dog-cutout.webp` | Transparent manufacturer original | https://drive.google.com/file/d/1zVF6Oot2pcGTTTQFEe6TzjPAis95cQfR/view |
| world-extra-stiegl | `/assets/beer-world-extra-stiegl-cutout.webp` | Background extraction with built-in image_gen | https://www.stiegl.at/wp-content/uploads/2022/01/produktgruppe-gb.png |
| ru-bakunin-rubin | `/assets/beer-rus-extra-bakunin-rubin-cutout.webp` | Transparent manufacturer original | https://drive.google.com/file/d/1atjzRpoQJ-kwAjb4ooChkZECoByxccuC/view |
| ru-bakunin-chistyi | `/assets/beer-rus-extra-bakunin-chistyi-cutout.webp` | Background extraction with built-in image_gen | https://static.tildacdn.com/tild3864-3637-4531-b333-656338393062/reg_copy3.jpg |
| world-extra-einstok | `/assets/beer-world-extra-einstok-cutout.webp` | Transparent manufacturer original | https://einstokbeer.com/wp-content/uploads/2017/04/white-ale-blaut_clip.png |
| ru-jaws-black-ipa | `/assets/beer-rus-extra-jaws-black-ipa-cutout.webp` | Transparent manufacturer original | https://static.tildacdn.com/tild3634-6639-4838-a338-323465343130/src_35.png |
| world-extra-asahi | `/assets/beer-world-extra-asahi-cutout.webp` | Background extraction with built-in image_gen | https://www.asahideutschland.de/assets/images/8/Asahi_Flasche033l_Condensation-45332085.png |
| ru-jaws-om | `/assets/beer-rus-extra-jaws-om-cutout.webp` | Transparent manufacturer original | https://static.tildacdn.com/tild6161-3034-4339-a330-393036663939/bottle_033_Jaws_OM.png |
| ru-jaws-jazz-mango | `/assets/beer-rus-extra-jaws-jazz-mango-cutout.webp` | Transparent manufacturer original | https://static.tildacdn.com/tild6337-6461-4661-b061-623962386563/bottle_05_Jaws_JazzJ.png |
| world-extra-carlsberg | `/assets/beer-world-extra-carlsberg-cutout.webp` | Background extraction with built-in image_gen | https://www.carlsberg.com/media/3txhrmiz/carlsberg-pilsner-beer-thumbnail.png |
| world-extra-estrella | `/assets/beer-world-extra-estrella-cutout.webp` | Transparent manufacturer original | https://www.damm.com/sites/default/files/config-pages/beer_information_image_bottle/estrella-damm_0.png |
