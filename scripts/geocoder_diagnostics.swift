#!/usr/bin/env swift

import Foundation
import CoreLocation

// ─────────────────────────────────────────────────────────
// Apple CLGeocoder Country Diagnostics
// Run: swift scripts/geocoder_diagnostics.swift
// ─────────────────────────────────────────────────────────

struct Point {
    let iso2: String
    let label: String
    let lat: Double
    let lon: Double
}

let samplePoints: [Point] = [
    .init(iso2: "AD", label: "Andorra la Vella", lat: 42.5063, lon: 1.5218),
    .init(iso2: "AE", label: "Dubai-center", lat: 25.2048, lon: 55.2708),
    .init(iso2: "AE", label: "Abu Dhabi-center", lat: 24.4539, lon: 54.3773),
    .init(iso2: "AF", label: "Kabul-center", lat: 34.5553, lon: 69.2075),
    .init(iso2: "AF", label: "Herat-center", lat: 34.3529, lon: 62.2040),
    .init(iso2: "AG", label: "St Johns-Antigua", lat: 17.1274, lon: -61.8468),
    .init(iso2: "AI", label: "The Valley", lat: 18.2206, lon: -63.0686),
    .init(iso2: "AL", label: "Tirana-center", lat: 41.3275, lon: 19.8187),
    .init(iso2: "AM", label: "Yerevan-center", lat: 40.1792, lon: 44.4991),
    .init(iso2: "AO", label: "Luanda-center", lat: -8.8390, lon: 13.2894),
    .init(iso2: "AO", label: "Huambo-center", lat: -12.7764, lon: 15.7394),
    .init(iso2: "AR", label: "Buenos Aires-center", lat: -34.6037, lon: -58.3816),
    .init(iso2: "AR", label: "Cordoba-AR-center", lat: -31.4201, lon: -64.1888),
    .init(iso2: "AS", label: "Pago Pago", lat: -14.2756, lon: -170.7020),
    .init(iso2: "AT", label: "Vienna-center", lat: 48.2082, lon: 16.3738),
    .init(iso2: "AU", label: "Sydney-center", lat: -33.8688, lon: 151.2093),
    .init(iso2: "AU", label: "Melbourne-center", lat: -37.8136, lon: 144.9631),
    .init(iso2: "AW", label: "Oranjestad", lat: 12.5092, lon: -70.0086),
    .init(iso2: "AX", label: "Mariehamn", lat: 60.0970, lon: 19.9348),
    .init(iso2: "AZ", label: "Baku-center", lat: 40.4093, lon: 49.8671),
    .init(iso2: "AZ", label: "Ganja-center", lat: 40.6828, lon: 46.3606),
    .init(iso2: "BA", label: "Sarajevo-center", lat: 43.8563, lon: 18.4131),
    .init(iso2: "BB", label: "Bridgetown-center", lat: 13.0969, lon: -59.6145),
    .init(iso2: "BD", label: "Dhaka-center", lat: 23.8103, lon: 90.4125),
    .init(iso2: "BD", label: "Chittagong-center", lat: 22.3569, lon: 91.7832),
    .init(iso2: "BE", label: "Brussels-center", lat: 50.8503, lon: 4.3517),
    .init(iso2: "BE", label: "Antwerp-center", lat: 51.2194, lon: 4.4025),
    .init(iso2: "BF", label: "Ouagadougou-center", lat: 12.3714, lon: -1.5197),
    .init(iso2: "BF", label: "Bobo-Dioulasso", lat: 11.1771, lon: -4.2979),
    .init(iso2: "BG", label: "Sofia-center", lat: 42.6977, lon: 23.3219),
    .init(iso2: "BH", label: "Manama-center", lat: 26.2285, lon: 50.5860),
    .init(iso2: "BI", label: "Gitega-center", lat: -3.4264, lon: 29.9246),
    .init(iso2: "BI", label: "Bujumbura-center", lat: -3.3614, lon: 29.3599),
    .init(iso2: "BJ", label: "Porto-Novo-center", lat: 6.4969, lon: 2.6289),
    .init(iso2: "BJ", label: "Cotonou-center", lat: 6.3703, lon: 2.3912),
    .init(iso2: "BL", label: "Gustavia", lat: 17.8958, lon: -62.8508),
    .init(iso2: "BM", label: "Hamilton-BM", lat: 32.2949, lon: -64.7820),
    .init(iso2: "BN", label: "Bandar Seri Begawan", lat: 4.9031, lon: 114.9398),
    .init(iso2: "BO", label: "La Paz-center", lat: -16.4897, lon: -68.1193),
    .init(iso2: "BO", label: "Santa Cruz-BO", lat: -17.7833, lon: -63.1821),
    .init(iso2: "BQ", label: "Kralendijk", lat: 12.1443, lon: -68.2655),
    .init(iso2: "BR", label: "Sao Paulo-center", lat: -23.5505, lon: -46.6333),
    .init(iso2: "BR", label: "Rio-center", lat: -22.9068, lon: -43.1729),
    .init(iso2: "BS", label: "Nassau-center", lat: 25.0343, lon: -77.3963),
    .init(iso2: "BT", label: "Thimphu-center", lat: 27.4728, lon: 89.6393),
    .init(iso2: "BW", label: "Gaborone-center", lat: -24.6282, lon: 25.9231),
    .init(iso2: "BY", label: "Minsk-center", lat: 53.9045, lon: 27.5615),
    .init(iso2: "BY", label: "Gomel-center", lat: 52.4345, lon: 30.9754),
    .init(iso2: "BZ", label: "Belmopan-center", lat: 17.2510, lon: -88.7590),
    .init(iso2: "CA", label: "Toronto-center", lat: 43.6532, lon: -79.3832),
    .init(iso2: "CA", label: "Vancouver-center", lat: 49.2827, lon: -123.1207),
    .init(iso2: "CD", label: "Kinshasa-center", lat: -4.4419, lon: 15.2663),
    .init(iso2: "CD", label: "Lubumbashi-center", lat: -11.6647, lon: 27.4794),
    .init(iso2: "CF", label: "Bangui-center", lat: 4.3947, lon: 18.5582),
    .init(iso2: "CG", label: "Brazzaville-center", lat: -4.2634, lon: 15.2429),
    .init(iso2: "CH", label: "Zurich-center", lat: 47.3769, lon: 8.5417),
    .init(iso2: "CI", label: "Abidjan-center", lat: 5.3600, lon: -4.0083),
    .init(iso2: "CI", label: "Yamoussoukro-center", lat: 6.8276, lon: -5.2893),
    .init(iso2: "CK", label: "Avarua", lat: -21.2075, lon: -159.7750),
    .init(iso2: "CL", label: "Santiago-center", lat: -33.4489, lon: -70.6693),
    .init(iso2: "CL", label: "Valparaiso-center", lat: -33.0472, lon: -71.6127),
    .init(iso2: "CM", label: "Yaounde-center", lat: 3.8480, lon: 11.5021),
    .init(iso2: "CM", label: "Douala-center", lat: 4.0511, lon: 9.7679),
    .init(iso2: "CN", label: "Beijing-center", lat: 39.9042, lon: 116.4074),
    .init(iso2: "CN", label: "Shanghai-center", lat: 31.2304, lon: 121.4737),
    .init(iso2: "CO", label: "Bogota-center", lat: 4.7110, lon: -74.0721),
    .init(iso2: "CO", label: "Medellin-center", lat: 6.2476, lon: -75.5658),
    .init(iso2: "CR", label: "San Jose-CR-center", lat: 9.9281, lon: -84.0907),
    .init(iso2: "CU", label: "Havana-center", lat: 23.1136, lon: -82.3666),
    .init(iso2: "CU", label: "Santiago de Cuba", lat: 20.0169, lon: -75.8301),
    .init(iso2: "CV", label: "Praia-center", lat: 14.9331, lon: -23.5133),
    .init(iso2: "CW", label: "Willemstad-center", lat: 12.1696, lon: -68.9900),
    .init(iso2: "CX", label: "Flying Fish Cove", lat: -10.4217, lon: 105.6791),
    .init(iso2: "CY", label: "Nicosia-center", lat: 35.1856, lon: 33.3823),
    .init(iso2: "CZ", label: "Prague-center", lat: 50.0755, lon: 14.4378),
    .init(iso2: "CZ", label: "Brno-center", lat: 49.1951, lon: 16.6068),
    .init(iso2: "DE", label: "Berlin-center", lat: 52.5200, lon: 13.4050),
    .init(iso2: "DE", label: "Munich-center", lat: 48.1351, lon: 11.5820),
    .init(iso2: "DJ", label: "Djibouti-center", lat: 11.5721, lon: 43.1456),
    .init(iso2: "DK", label: "Copenhagen-center", lat: 55.6761, lon: 12.5683),
    .init(iso2: "DM", label: "Roseau-center", lat: 15.3010, lon: -61.3880),
    .init(iso2: "DO", label: "Santo Domingo-center", lat: 18.4861, lon: -69.9312),
    .init(iso2: "DO", label: "Santiago-DO-center", lat: 19.4517, lon: -70.6970),
    .init(iso2: "DZ", label: "Algiers-center", lat: 36.7538, lon: 3.0588),
    .init(iso2: "DZ", label: "Oran-center", lat: 35.6969, lon: -0.6331),
    .init(iso2: "EC", label: "Quito-center", lat: -0.1807, lon: -78.4678),
    .init(iso2: "EC", label: "Guayaquil-center", lat: -2.1710, lon: -79.9224),
    .init(iso2: "EE", label: "Tallinn-center", lat: 59.4370, lon: 24.7536),
    .init(iso2: "EG", label: "Cairo-center", lat: 30.0444, lon: 31.2357),
    .init(iso2: "EG", label: "Alexandria-center", lat: 31.2001, lon: 29.9187),
    .init(iso2: "ER", label: "Asmara-center", lat: 15.3229, lon: 38.9251),
    .init(iso2: "ES", label: "Madrid-center", lat: 40.4168, lon: -3.7038),
    .init(iso2: "ES", label: "Barcelona-center", lat: 41.3874, lon: 2.1686),
    .init(iso2: "ET", label: "Addis Ababa-center", lat: 9.0250, lon: 38.7469),
    .init(iso2: "ET", label: "Dire Dawa-center", lat: 9.5931, lon: 41.8661),
    .init(iso2: "FI", label: "Helsinki-center", lat: 60.1699, lon: 24.9384),
    .init(iso2: "FJ", label: "Suva-center", lat: -18.1416, lon: 178.4419),
    .init(iso2: "FK", label: "Stanley-FK", lat: -51.6975, lon: -57.8518),
    .init(iso2: "FM", label: "Palikir-center", lat: 6.9248, lon: 158.1610),
    .init(iso2: "FO", label: "Torshavn-center", lat: 62.0107, lon: -6.7741),
    .init(iso2: "FR", label: "Paris-center", lat: 48.8566, lon: 2.3522),
    .init(iso2: "FR", label: "Lyon-center", lat: 45.7640, lon: 4.8357),
    .init(iso2: "GA", label: "Libreville-center", lat: 0.4162, lon: 9.4673),
    .init(iso2: "GB", label: "London-center", lat: 51.5074, lon: -0.1278),
    .init(iso2: "GB", label: "Manchester-center", lat: 53.4808, lon: -2.2426),
    .init(iso2: "GD", label: "St Georges-GD", lat: 12.0561, lon: -61.7488),
    .init(iso2: "GE", label: "Tbilisi-center", lat: 41.7151, lon: 44.8271),
    .init(iso2: "GF", label: "Cayenne-center", lat: 4.9224, lon: -52.3135),
    .init(iso2: "GG", label: "St Peter Port", lat: 49.4555, lon: -2.5368),
    .init(iso2: "GH", label: "Accra-center", lat: 5.6037, lon: -0.1870),
    .init(iso2: "GH", label: "Kumasi-center", lat: 6.6885, lon: -1.6244),
    .init(iso2: "GI", label: "Gibraltar-center", lat: 36.1408, lon: -5.3536),
    .init(iso2: "GL", label: "Nuuk-center", lat: 64.1814, lon: -51.6941),
    .init(iso2: "GM", label: "Banjul-center", lat: 13.4549, lon: -16.5790),
    .init(iso2: "GN", label: "Conakry-center", lat: 9.6412, lon: -13.5784),
    .init(iso2: "GN", label: "Nzerekore-center", lat: 7.7562, lon: -8.8179),
    .init(iso2: "GP", label: "Basse-Terre-GP", lat: 15.9979, lon: -61.7321),
    .init(iso2: "GQ", label: "Malabo-center", lat: 3.7504, lon: 8.7371),
    .init(iso2: "GR", label: "Athens-center", lat: 37.9838, lon: 23.7275),
    .init(iso2: "GR", label: "Thessaloniki-center", lat: 40.6401, lon: 22.9444),
    .init(iso2: "GT", label: "Guatemala City", lat: 14.6349, lon: -90.5069),
    .init(iso2: "GT", label: "Quetzaltenango", lat: 14.8347, lon: -91.5188),
    .init(iso2: "GU", label: "Hagatna-center", lat: 13.4443, lon: 144.7937),
    .init(iso2: "GW", label: "Bissau-center", lat: 11.8816, lon: -15.6178),
    .init(iso2: "GY", label: "Georgetown-GY", lat: 6.8013, lon: -58.1551),
    .init(iso2: "HK", label: "Hong Kong-center", lat: 22.3193, lon: 114.1694),
    .init(iso2: "HN", label: "Tegucigalpa-center", lat: 14.0723, lon: -87.1921),
    .init(iso2: "HR", label: "Zagreb-center", lat: 45.8150, lon: 15.9819),
    .init(iso2: "HT", label: "Port-au-Prince", lat: 18.5944, lon: -72.3074),
    .init(iso2: "HT", label: "Cap-Haitien", lat: 19.7578, lon: -72.2044),
    .init(iso2: "HU", label: "Budapest-center", lat: 47.4979, lon: 19.0402),
    .init(iso2: "ID", label: "Jakarta-center", lat: -6.2088, lon: 106.8456),
    .init(iso2: "ID", label: "Surabaya-center", lat: -7.2575, lon: 112.7521),
    .init(iso2: "IE", label: "Dublin-center", lat: 53.3498, lon: -6.2603),
    .init(iso2: "IL", label: "Tel Aviv-center", lat: 32.0853, lon: 34.7818),
    .init(iso2: "IL", label: "Jerusalem-center", lat: 31.7683, lon: 35.2137),
    .init(iso2: "IM", label: "Douglas-IM", lat: 54.1523, lon: -4.4860),
    .init(iso2: "IN", label: "New Delhi-center", lat: 28.6139, lon: 77.2090),
    .init(iso2: "IN", label: "Mumbai-center", lat: 19.0760, lon: 72.8777),
    .init(iso2: "IQ", label: "Baghdad-center", lat: 33.3152, lon: 44.3661),
    .init(iso2: "IQ", label: "Basra-center", lat: 30.5085, lon: 47.7804),
    .init(iso2: "IR", label: "Tehran-center", lat: 35.6892, lon: 51.3890),
    .init(iso2: "IR", label: "Isfahan-center", lat: 32.6546, lon: 51.6680),
    .init(iso2: "IS", label: "Reykjavik-center", lat: 64.1466, lon: -21.9426),
    .init(iso2: "IT", label: "Rome-center", lat: 41.9028, lon: 12.4964),
    .init(iso2: "IT", label: "Milan-center", lat: 45.4642, lon: 9.1900),
    .init(iso2: "JE", label: "St Helier", lat: 49.1880, lon: -2.1049),
    .init(iso2: "JM", label: "Kingston-JM", lat: 18.0179, lon: -76.8099),
    .init(iso2: "JO", label: "Amman-center", lat: 31.9454, lon: 35.9284),
    .init(iso2: "JO", label: "Zarqa-center", lat: 32.0728, lon: 36.0880),
    .init(iso2: "JP", label: "Tokyo-center", lat: 35.6762, lon: 139.6503),
    .init(iso2: "JP", label: "Osaka-center", lat: 34.6937, lon: 135.5023),
    .init(iso2: "KE", label: "Nairobi-center", lat: -1.2921, lon: 36.8219),
    .init(iso2: "KE", label: "Mombasa-center", lat: -4.0435, lon: 39.6682),
    .init(iso2: "KG", label: "Bishkek-center", lat: 42.8746, lon: 74.5698),
    .init(iso2: "KH", label: "Phnom Penh-center", lat: 11.5564, lon: 104.9282),
    .init(iso2: "KH", label: "Siem Reap-center", lat: 13.3633, lon: 103.8564),
    .init(iso2: "KI", label: "Tarawa-center", lat: 1.4518, lon: 173.0186),
    .init(iso2: "KM", label: "Moroni-center", lat: -11.7022, lon: 43.2551),
    .init(iso2: "KN", label: "Basseterre-center", lat: 17.3026, lon: -62.7177),
    .init(iso2: "KP", label: "Pyongyang-center", lat: 39.0392, lon: 125.7625),
    .init(iso2: "KR", label: "Seoul-center", lat: 37.5665, lon: 126.9780),
    .init(iso2: "KR", label: "Busan-center", lat: 35.1796, lon: 129.0756),
    .init(iso2: "KW", label: "Kuwait City", lat: 29.3759, lon: 47.9774),
    .init(iso2: "KY", label: "George Town-KY", lat: 19.2869, lon: -81.3674),
    .init(iso2: "KZ", label: "Astana-center", lat: 51.1694, lon: 71.4491),
    .init(iso2: "KZ", label: "Almaty-center", lat: 43.2380, lon: 76.9458),
    .init(iso2: "LA", label: "Vientiane-center", lat: 17.9757, lon: 102.6331),
    .init(iso2: "LB", label: "Beirut-center", lat: 33.8938, lon: 35.5018),
    .init(iso2: "LC", label: "Castries-center", lat: 14.0101, lon: -60.9870),
    .init(iso2: "LI", label: "Vaduz-center", lat: 47.1410, lon: 9.5215),
    .init(iso2: "LK", label: "Colombo-center", lat: 6.9271, lon: 79.8612),
    .init(iso2: "LK", label: "Kandy-center", lat: 7.2906, lon: 80.6337),
    .init(iso2: "LR", label: "Monrovia-center", lat: 6.2907, lon: -10.7605),
    .init(iso2: "LS", label: "Maseru-center", lat: -29.3142, lon: 27.4833),
    .init(iso2: "LT", label: "Vilnius-center", lat: 54.6872, lon: 25.2797),
    .init(iso2: "LU", label: "Luxembourg City", lat: 49.6117, lon: 6.1319),
    .init(iso2: "LV", label: "Riga-center", lat: 56.9496, lon: 24.1052),
    .init(iso2: "LY", label: "Tripoli-center", lat: 32.8872, lon: 13.1913),
    .init(iso2: "MA", label: "Rabat-center", lat: 34.0209, lon: -6.8416),
    .init(iso2: "MA", label: "Casablanca-center", lat: 33.5731, lon: -7.5898),
    .init(iso2: "MC", label: "Monaco-center", lat: 43.7384, lon: 7.4246),
    .init(iso2: "MD", label: "Chisinau-center", lat: 47.0105, lon: 28.8638),
    .init(iso2: "ME", label: "Podgorica-center", lat: 42.4304, lon: 19.2594),
    .init(iso2: "MF", label: "Marigot-center", lat: 18.0732, lon: -63.0822),
    .init(iso2: "MG", label: "Antananarivo-center", lat: -18.8792, lon: 47.5079),
    .init(iso2: "MG", label: "Toamasina-center", lat: -18.1496, lon: 49.4023),
    .init(iso2: "MH", label: "Majuro-center", lat: 7.1164, lon: 171.1858),
    .init(iso2: "MK", label: "Skopje-center", lat: 41.9973, lon: 21.4280),
    .init(iso2: "ML", label: "Bamako-center", lat: 12.6392, lon: -8.0029),
    .init(iso2: "ML", label: "Sikasso-center", lat: 11.3175, lon: -5.6664),
    .init(iso2: "MM", label: "Yangon-center", lat: 16.8661, lon: 96.1951),
    .init(iso2: "MM", label: "Mandalay-center", lat: 21.9588, lon: 96.0891),
    .init(iso2: "MN", label: "Ulaanbaatar-center", lat: 47.8864, lon: 106.9057),
    .init(iso2: "MO", label: "Macau-center", lat: 22.1987, lon: 113.5439),
    .init(iso2: "MP", label: "Saipan-center", lat: 15.1772, lon: 145.7505),
    .init(iso2: "MQ", label: "Fort-de-France", lat: 14.6161, lon: -61.0588),
    .init(iso2: "MR", label: "Nouakchott-center", lat: 18.0735, lon: -15.9582),
    .init(iso2: "MS", label: "Brades-center", lat: 16.7928, lon: -62.2106),
    .init(iso2: "MT", label: "Valletta-center", lat: 35.8989, lon: 14.5146),
    .init(iso2: "MU", label: "Port Louis-center", lat: -20.1609, lon: 57.5012),
    .init(iso2: "MV", label: "Male-center", lat: 4.1755, lon: 73.5093),
    .init(iso2: "MW", label: "Lilongwe-center", lat: -13.9626, lon: 33.7741),
    .init(iso2: "MW", label: "Blantyre-center", lat: -15.7667, lon: 35.0168),
    .init(iso2: "MX", label: "Mexico City-center", lat: 19.4326, lon: -99.1332),
    .init(iso2: "MX", label: "Guadalajara-center", lat: 20.6597, lon: -103.3496),
    .init(iso2: "MY", label: "Kuala Lumpur-center", lat: 3.1390, lon: 101.6869),
    .init(iso2: "MY", label: "George Town-MY", lat: 5.4141, lon: 100.3288),
    .init(iso2: "MZ", label: "Maputo-center", lat: -25.9692, lon: 32.5732),
    .init(iso2: "MZ", label: "Beira-center", lat: -19.8436, lon: 34.8389),
    .init(iso2: "NA", label: "Windhoek-center", lat: -22.5609, lon: 17.0658),
    .init(iso2: "NC", label: "Noumea-center", lat: -22.2558, lon: 166.4505),
    .init(iso2: "NE", label: "Niamey-center", lat: 13.5127, lon: 2.1128),
    .init(iso2: "NE", label: "Zinder-center", lat: 13.8053, lon: 8.9880),
    .init(iso2: "NG", label: "Lagos-center", lat: 6.5244, lon: 3.3792),
    .init(iso2: "NG", label: "Abuja-center", lat: 9.0579, lon: 7.4951),
    .init(iso2: "NI", label: "Managua-center", lat: 12.1150, lon: -86.2362),
    .init(iso2: "NL", label: "Amsterdam-center", lat: 52.3676, lon: 4.9041),
    .init(iso2: "NL", label: "Rotterdam-center", lat: 51.9244, lon: 4.4777),
    .init(iso2: "NO", label: "Oslo-center", lat: 59.9139, lon: 10.7522),
    .init(iso2: "NP", label: "Kathmandu-center", lat: 27.7172, lon: 85.3240),
    .init(iso2: "NP", label: "Pokhara-center", lat: 28.2096, lon: 83.9856),
    .init(iso2: "NR", label: "Yaren-center", lat: -0.5477, lon: 166.9209),
    .init(iso2: "NU", label: "Alofi-center", lat: -19.0590, lon: -169.9210),
    .init(iso2: "NZ", label: "Auckland-center", lat: -36.8485, lon: 174.7633),
    .init(iso2: "OM", label: "Muscat-center", lat: 23.5880, lon: 58.3829),
    .init(iso2: "PA", label: "Panama City-center", lat: 8.9824, lon: -79.5199),
    .init(iso2: "PE", label: "Lima-center", lat: -12.0464, lon: -77.0428),
    .init(iso2: "PE", label: "Arequipa-center", lat: -16.4090, lon: -71.5375),
    .init(iso2: "PF", label: "Papeete-center", lat: -17.5516, lon: -149.5585),
    .init(iso2: "PG", label: "Port Moresby", lat: -6.3149, lon: 143.9555),
    .init(iso2: "PH", label: "Manila-center", lat: 14.5995, lon: 120.9842),
    .init(iso2: "PH", label: "Cebu-center", lat: 10.3157, lon: 123.8854),
    .init(iso2: "PK", label: "Karachi-center", lat: 24.8607, lon: 67.0011),
    .init(iso2: "PK", label: "Lahore-center", lat: 31.5204, lon: 74.3587),
    .init(iso2: "PL", label: "Warsaw-center", lat: 52.2297, lon: 21.0122),
    .init(iso2: "PL", label: "Krakow-center", lat: 50.0647, lon: 19.9450),
    .init(iso2: "PR", label: "San Juan-PR", lat: 18.4655, lon: -66.1057),
    .init(iso2: "PS", label: "Ramallah-center", lat: 31.9038, lon: 35.2034),
    .init(iso2: "PT", label: "Lisbon-center", lat: 38.7223, lon: -9.1393),
    .init(iso2: "PT", label: "Porto-center", lat: 41.1579, lon: -8.6291),
    .init(iso2: "PW", label: "Ngerulmud-center", lat: 7.5006, lon: 134.6242),
    .init(iso2: "PY", label: "Asuncion-center", lat: -25.2637, lon: -57.5759),
    .init(iso2: "QA", label: "Doha-center", lat: 25.2854, lon: 51.5310),
    .init(iso2: "RE", label: "Saint-Denis-RE", lat: -20.8823, lon: 55.4504),
    .init(iso2: "RO", label: "Bucharest-center", lat: 44.4268, lon: 26.1025),
    .init(iso2: "RO", label: "Cluj-Napoca-center", lat: 46.7712, lon: 23.6236),
    .init(iso2: "RS", label: "Belgrade-center", lat: 44.7866, lon: 20.4489),
    .init(iso2: "RU", label: "Moscow-center", lat: 55.7558, lon: 37.6173),
    .init(iso2: "RU", label: "St Petersburg", lat: 59.9343, lon: 30.3351),
    .init(iso2: "RW", label: "Kigali-center", lat: -1.9403, lon: 29.8739),
    .init(iso2: "SA", label: "Riyadh-center", lat: 24.7136, lon: 46.6753),
    .init(iso2: "SA", label: "Jeddah-center", lat: 21.4858, lon: 39.1925),
    .init(iso2: "SB", label: "Honiara-center", lat: -9.4456, lon: 159.9729),
    .init(iso2: "SC", label: "Victoria-SC", lat: -4.6191, lon: 55.4513),
    .init(iso2: "SD", label: "Khartoum-center", lat: 15.5007, lon: 32.5599),
    .init(iso2: "SD", label: "Omdurman-center", lat: 15.6445, lon: 32.4777),
    .init(iso2: "SE", label: "Stockholm-center", lat: 59.3293, lon: 18.0686),
    .init(iso2: "SE", label: "Gothenburg-center", lat: 57.7089, lon: 11.9746),
    .init(iso2: "SG", label: "Singapore-center", lat: 1.3521, lon: 103.8198),
    .init(iso2: "SI", label: "Ljubljana-center", lat: 46.0569, lon: 14.5058),
    .init(iso2: "SK", label: "Bratislava-center", lat: 48.1486, lon: 17.1077),
    .init(iso2: "SL", label: "Freetown-center", lat: 8.4657, lon: -13.2317),
    .init(iso2: "SM", label: "San Marino-center", lat: 43.9424, lon: 12.4578),
    .init(iso2: "SN", label: "Dakar-center", lat: 14.7167, lon: -17.4677),
    .init(iso2: "SN", label: "Thies-center", lat: 14.7886, lon: -16.9260),
    .init(iso2: "SO", label: "Mogadishu-center", lat: 2.0469, lon: 45.3182),
    .init(iso2: "SR", label: "Paramaribo-center", lat: 5.8520, lon: -55.2038),
    .init(iso2: "SS", label: "Juba-center", lat: 4.8594, lon: 31.5713),
    .init(iso2: "ST", label: "Sao Tome-center", lat: 0.3302, lon: 6.7335),
    .init(iso2: "SV", label: "San Salvador", lat: 13.6929, lon: -89.2182),
    .init(iso2: "SX", label: "Philipsburg-center", lat: 18.0260, lon: -63.0458),
    .init(iso2: "SY", label: "Damascus-center", lat: 33.5138, lon: 36.2765),
    .init(iso2: "SZ", label: "Mbabane-center", lat: -26.3054, lon: 31.1367),
    .init(iso2: "TC", label: "Cockburn Town", lat: 21.4612, lon: -71.1419),
    .init(iso2: "TD", label: "NDjamena-center", lat: 12.1348, lon: 15.0557),
    .init(iso2: "TG", label: "Lome-center", lat: 6.1256, lon: 1.2254),
    .init(iso2: "TH", label: "Bangkok-center", lat: 13.7563, lon: 100.5018),
    .init(iso2: "TH", label: "Chiang Mai-center", lat: 18.7883, lon: 98.9853),
    .init(iso2: "TJ", label: "Dushanbe-center", lat: 38.5598, lon: 68.7740),
    .init(iso2: "TL", label: "Dili-center", lat: -8.5569, lon: 125.5603),
    .init(iso2: "TM", label: "Ashgabat-center", lat: 37.9601, lon: 58.3261),
    .init(iso2: "TN", label: "Tunis-center", lat: 36.8065, lon: 10.1815),
    .init(iso2: "TN", label: "Sfax-center", lat: 34.7398, lon: 10.7600),
    .init(iso2: "TO", label: "Nukualofa-center", lat: -21.2094, lon: -175.1982),
    .init(iso2: "TR", label: "Istanbul-center", lat: 41.0082, lon: 28.9784),
    .init(iso2: "TR", label: "Ankara-center", lat: 39.9334, lon: 32.8597),
    .init(iso2: "TT", label: "Port of Spain", lat: 10.6596, lon: -61.5086),
    .init(iso2: "TV", label: "Funafuti-center", lat: -8.5212, lon: 179.1983),
    .init(iso2: "TW", label: "Taipei-center", lat: 25.0330, lon: 121.5654),
    .init(iso2: "TW", label: "Kaohsiung-center", lat: 22.6273, lon: 120.3014),
    .init(iso2: "TZ", label: "Dar es Salaam", lat: -6.7924, lon: 39.2083),
    .init(iso2: "TZ", label: "Dodoma-center", lat: -6.1630, lon: 35.7516),
    .init(iso2: "UA", label: "Kyiv-center", lat: 50.4501, lon: 30.5234),
    .init(iso2: "UA", label: "Kharkiv-center", lat: 49.9935, lon: 36.2304),
    .init(iso2: "UG", label: "Kampala-center", lat: 0.3476, lon: 32.5825),
    .init(iso2: "UG", label: "Gulu-center", lat: 2.7746, lon: 32.2990),
    .init(iso2: "US", label: "New York-center", lat: 40.7128, lon: -74.0060),
    .init(iso2: "US", label: "Los Angeles-center", lat: 34.0522, lon: -118.2437),
    .init(iso2: "UY", label: "Montevideo-center", lat: -34.9011, lon: -56.1645),
    .init(iso2: "UZ", label: "Tashkent-center", lat: 41.2995, lon: 69.2401),
    .init(iso2: "UZ", label: "Samarkand-center", lat: 39.6542, lon: 66.9597),
    .init(iso2: "VA", label: "Vatican City", lat: 41.9029, lon: 12.4534),
    .init(iso2: "VC", label: "Kingstown-VC", lat: 13.1587, lon: -61.2248),
    .init(iso2: "VE", label: "Caracas-center", lat: 10.4806, lon: -66.9036),
    .init(iso2: "VE", label: "Maracaibo-center", lat: 10.6317, lon: -71.6406),
    .init(iso2: "VG", label: "Road Town-center", lat: 18.4286, lon: -64.6185),
    .init(iso2: "VI", label: "Charlotte Amalie", lat: 18.3358, lon: -64.9307),
    .init(iso2: "VN", label: "Hanoi-center", lat: 21.0278, lon: 105.8342),
    .init(iso2: "VN", label: "Ho Chi Minh-center", lat: 10.8231, lon: 106.6297),
    .init(iso2: "VU", label: "Port Vila-center", lat: -17.7334, lon: 168.3273),
    .init(iso2: "WS", label: "Apia-center", lat: -13.8333, lon: -171.7500),
    .init(iso2: "XK", label: "Pristina-center", lat: 42.6629, lon: 21.1655),
    .init(iso2: "YE", label: "Sanaa-center", lat: 15.3694, lon: 44.1910),
    .init(iso2: "YE", label: "Aden-center", lat: 12.7855, lon: 45.0187),
    .init(iso2: "YT", label: "Mamoudzou-center", lat: -12.7871, lon: 45.2750),
    .init(iso2: "ZA", label: "Johannesburg", lat: -26.2041, lon: 28.0473),
    .init(iso2: "ZA", label: "Cape Town-center", lat: -33.9249, lon: 18.4241),
    .init(iso2: "ZM", label: "Lusaka-center", lat: -15.3875, lon: 28.3228),
    .init(iso2: "ZM", label: "Kitwe-center", lat: -12.8025, lon: 28.2132),
    .init(iso2: "ZW", label: "Harare-center", lat: -17.8252, lon: 31.0335),
    .init(iso2: "ZW", label: "Bulawayo-center", lat: -20.1487, lon: 28.5878),
]

// ─────────────────────────────────────────────────────────

let geocoder = CLGeocoder()
let locale = Locale(identifier: "en_US")
struct Row {
    let iso2: String
    let label: String
    let locality: String?
    let subAdmin: String?
    let admin: String?
    let country: String?
}

var results: [Row] = []

func pad(_ s: String?, width: Int) -> String {
    let str = s ?? "nil"
    return str.padding(toLength: width, withPad: " ", startingAt: 0)
}

print("")
print(String(repeating: "=", count: 120))
print("GEOCODER COUNTRY DIAGNOSTICS — \(samplePoints.count) points")
print(String(repeating: "=", count: 120))
print("\(pad("ISO", width: 5))\(pad("Label", width: 24))\(pad("locality", width: 26))\(pad("subAdminArea", width: 26))\(pad("adminArea", width: 26))\(pad("country", width: 20))")
print(String(repeating: "-", count: 120))

var index = 0

func processNext() {
    guard index < samplePoints.count else {
        // Print summary
        print("")
        print(String(repeating: "=", count: 90))
        print("SUMMARY — Field availability per country")
        print(String(repeating: "=", count: 90))
        print("\(pad("ISO", width: 6))\(pad("locality", width: 12))\(pad("subAdmin", width: 12))\(pad("admin", width: 12))\(pad("country", width: 12))Suggested")
        print(String(repeating: "-", count: 90))

        let grouped = Dictionary(grouping: results, by: { $0.iso2 })
        for iso2 in grouped.keys.sorted() {
            let rows = grouped[iso2]!
            let n = rows.count
            let loc = rows.filter { $0.locality != nil }.count
            let sub = rows.filter { $0.subAdmin != nil }.count
            let adm = rows.filter { $0.admin != nil }.count
            let cty = rows.filter { $0.country != nil }.count

            let suggestion: String
            if loc == n && sub == n { suggestion = "locality or subAdmin (both always)" }
            else if loc == n { suggestion = "locality (always)" }
            else if sub == n { suggestion = "subAdmin (always)" }
            else if adm == n && loc == 0 && sub == 0 { suggestion = "admin (no finer data)" }
            else if adm == n { suggestion = "admin (finer levels partial)" }
            else { suggestion = "CHECK MANUALLY" }

            print("\(pad(iso2, width: 6))\(pad("\(loc)/\(n)", width: 12))\(pad("\(sub)/\(n)", width: 12))\(pad("\(adm)/\(n)", width: 12))\(pad("\(cty)/\(n)", width: 12))\(suggestion)")
        }
        print(String(repeating: "=", count: 90))
        print("Done.")
        done = true
        return
    }

    let point = samplePoints[index]
    let location = CLLocation(latitude: point.lat, longitude: point.lon)

    geocoder.reverseGeocodeLocation(location, preferredLocale: locale) { placemarks, error in
        if let error = error as NSError? {
            if error.domain == "GEOErrorDomain", error.code == -3 {
                print("  Throttled at \(point.label), waiting 15s...")
                DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                    geocoder.reverseGeocodeLocation(location, preferredLocale: locale) { pm2, err2 in
                        if let pm = pm2?.first {
                            let row = Row(iso2: point.iso2, label: point.label,
                                          locality: pm.locality, subAdmin: pm.subAdministrativeArea,
                                          admin: pm.administrativeArea, country: pm.country)
                            results.append(row)
                            print("\(pad(point.iso2, width: 5))\(pad(point.label, width: 24))\(pad(pm.locality, width: 26))\(pad(pm.subAdministrativeArea, width: 26))\(pad(pm.administrativeArea, width: 26))\(pad(pm.country, width: 20))")
                        } else {
                            print("\(pad(point.iso2, width: 5))\(pad(point.label, width: 24))ERROR (retry): \(err2?.localizedDescription ?? "no placemark")")
                        }
                        index += 1
                        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { processNext() }
                    }
                }
                return
            }
            print("\(pad(point.iso2, width: 5))\(pad(point.label, width: 24))ERROR: \(error.localizedDescription)")
            index += 1
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { processNext() }
            return
        }

        if let pm = placemarks?.first {
            let row = Row(iso2: point.iso2, label: point.label,
                          locality: pm.locality, subAdmin: pm.subAdministrativeArea,
                          admin: pm.administrativeArea, country: pm.country)
            results.append(row)
            print("\(pad(point.iso2, width: 5))\(pad(point.label, width: 24))\(pad(pm.locality, width: 26))\(pad(pm.subAdministrativeArea, width: 26))\(pad(pm.administrativeArea, width: 26))\(pad(pm.country, width: 20))")
        } else {
            print("\(pad(point.iso2, width: 5))\(pad(point.label, width: 24))(no placemark)")
        }

        index += 1
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { processNext() }
    }
}

var done = false

// Replace semaphore.signal() in processNext's completion with:
// done = true ; CFRunLoopStop(CFRunLoopGetMain())

processNext()

// Keep RunLoop alive so CLGeocoder callbacks fire
while !done {
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.5))
}
