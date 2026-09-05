# -*- coding: utf-8 -*-
"""Собирает TripTrack/Resources/VehicleCatalog.json из компактной таблицы ниже.

ИСТОЧНИК ПРАВДЫ — таблица DATA в этом файле, а не JSON: править список из ста
марок удобно строкой на марку, а не пятью строками на модель. JSON —
сгенерированный артефакт, который едет в бандл.

Формат строки:  Марка | Модель:кузов,кузов | Модель:кузов
Кузова названы ИМЕНАМИ СИЛУЭТОВ из VehicleAvatar.styles — выбор модели сразу
ставит правильный спрайт. Первый кузов в списке — тот, что подставляется.

Запуск:  python3 scripts/gen_vehicle_catalog.py   (из корня репозитория)
Потом:   xcodebuild test ... -only-testing:TripTrackTests/VehicleCatalogTests
"""
import json, sys

S = {"car","hatchback","crossover","pickup","van","convertible","sports",
     "motorcycle","scooter","bicycle"}

# Алиасы — то, как марку НАБИРАЮТ, а не то, как она пишется на кузове.
#
# Без них поиск не работает для рынка, ради которого каталог и собран: имя в
# списке одно, а человек печатает «тойота», «уаз» или «шкода». Проверено —
# до алиасов «уаз», «лада», «ваз», «GAZ» и «Moskvich» давали НОЛЬ совпадений.
#
# Канон названия — латиница (список читают на тринадцати языках, и «ГАЗ» в
# немецком интерфейсе нечитаем), кириллица живёт здесь. Лишний алиас безвреден:
# он просто никогда не совпадёт. Отсутствующий — это марка, которую не найти.
MAKE_ALIASES = {
 # Россия и СНГ
 "Lada": "Лада ВАЗ", "UAZ": "УАЗ", "GAZ": "ГАЗ", "Moskvich": "Москвич",
 "Datsun": "Датсун", "Ravon": "Равон", "Daewoo": "Дэу Дэо", "IZh": "ИЖ Izh",
 "Ural": "Урал", "Minsk": "Минск", "Aist": "Аист",
 # Япония
 "Toyota": "Тойота", "Honda": "Хонда", "Nissan": "Ниссан Нисан", "Mazda": "Мазда",
 "Mitsubishi": "Мицубиси Митсубиши", "Subaru": "Субару", "Suzuki": "Сузуки Судзуки",
 "Lexus": "Лексус", "Infiniti": "Инфинити", "Acura": "Акура",
 "Yamaha": "Ямаха", "Kawasaki": "Кавасаки",
 # Корея
 "Kia": "Киа Кия", "Hyundai": "Хендай Хундай Хёндэ", "Genesis": "Генезис",
 "SsangYong": "СангЙонг Ссангйонг",
 # Европа
 "Volkswagen": "Фольксваген VW Вольксваген", "Skoda": "Шкода Škoda",
 "Mercedes-Benz": "Мерседес Мерс Mercedes", "BMW": "БМВ", "Audi": "Ауди",
 "Opel": "Опель", "Porsche": "Порше Порш", "Mini": "Мини", "Renault": "Рено",
 "Peugeot": "Пежо", "Citroen": "Ситроен Citroën", "Fiat": "Фиат", "Iveco": "Ивеко",
 "Volvo": "Вольво", "Land Rover": "Ленд Ровер Лендровер Рендж Ровер",
 "Ducati": "Дукати", "Aprilia": "Априлия", "Vespa": "Веспа", "Piaggio": "Пьяджо",
 "Triumph": "Триумф", "KTM": "КТМ", "Seat": "Сеат Сиат",
 # США
 "Ford": "Форд", "Chevrolet": "Шевроле Шеви", "Jeep": "Джип", "Cadillac": "Кадиллак",
 "Dodge": "Додж", "Chrysler": "Крайслер", "Tesla": "Тесла",
 "Harley-Davidson": "Харлей Харлей-Дэвидсон Harley",
 # Китай
 "Chery": "Чери", "Haval": "Хавал Хавейл", "Geely": "Джили", "Exeed": "Эксид",
 "Omoda": "Омода", "Jetour": "Джетур", "Changan": "Чанган",
 "Great Wall": "Грейт Вол Грейтвол GWM", "Belgee": "Белджи", "Tank": "Танк",
 "Li Auto": "Ли Авто Лисян", "Zeekr": "Зикр", "Voyah": "Воях", "BYD": "БИД",
 "Hongqi": "Хончи", "JAC": "ДЖАК", "FAW": "ФАВ", "Dongfeng": "Дунфэн Донгфенг",
 "Kaiyi": "Кайи", "Livan": "Ливан", "Jaecoo": "Джейку", "BAIC": "БАИК", "Lifan": "Лифан",
 # Мото и велосипеды
 "CFMOTO": "ЦФМОТО СФМОТО", "Voge": "Воге", "Racer": "Рейсер",
 "Regulmoto": "Регулмото", "Stels": "Стелс", "Forward": "Форвард",
 "Merida": "Мерида", "Giant": "Джайант", "Trek": "Трек",
 "Specialized": "Спешелайзд", "Cube": "Кубе", "Author": "Аутор",
 "Format": "Формат", "Altair": "Альтаир", "Cannondale": "Каннондейл",
 "Scott": "Скотт", "Shulz": "Шульц",
}

# Модели, у которых народное имя не совпадает с заводским. Ключ — «Марка/Модель».
# «Буханка» тут не шутка: УАЗ 3909 по индексу не ищет никто.
MODEL_ALIASES = {
 "UAZ/3909": "Буханка Bukhanka Buhanka",
 "UAZ/Patriot": "Патриот", "UAZ/Hunter": "Хантер",
 "GAZ/GAZelle Next": "ГАЗель Газель Gazelle",
 "GAZ/GAZelle Business": "ГАЗель Газель Gazelle",
 "GAZ/Sobol": "Соболь", "GAZ/Volga 3110": "Волга", "GAZ/Volga 31105": "Волга",
 "IZh/Planeta 5": "Планета", "IZh/Jupiter 5": "Юпитер Jupiter", "IZh/Oda": "Ода",
 "Lada/Niva Legend": "Нива", "Lada/Niva Travel": "Нива Шевинива",
 "Lada/Granta": "Гранта", "Lada/Vesta": "Веста", "Lada/Kalina": "Калина",
 "Lada/Priora": "Приора", "Lada/Samara": "Самара", "Lada/Largus": "Ларгус",
 "Lada/Iskra": "Искра",
}

DATA = """
# ---- Россия и СНГ
Lada | Granta:car,hatchback | Vesta:car,hatchback | Niva Legend:crossover | Niva Travel:crossover | Largus:van | XRAY:hatchback | Kalina:hatchback | Priora:car | Samara:hatchback | 2107:car | 2114:hatchback | Iskra:car
UAZ | Patriot:crossover | Hunter:crossover | Pickup:pickup | 3909:van | Profi:van | 469:crossover
GAZ | GAZelle Next:van | GAZelle Business:van | Sobol:van | Volga 3110:car | Volga 31105:car
Moskvich | 3:crossover | 3e:crossover | 6:car | 8:crossover | 2141:hatchback | 2140:car
Datsun | on-DO:car | mi-DO:hatchback
Ravon | Nexia R3:car | R2:hatchback | Gentra:car
Daewoo | Nexia:car | Matiz:hatchback | Lanos:car | Espero:car
IZh | Planeta 5:motorcycle | Jupiter 5:motorcycle | Oda:hatchback
Ural | Gear Up:motorcycle | Retro:motorcycle | M70:motorcycle
Minsk | M1NSK C4:motorcycle | M1NSK X250:motorcycle | D4 125:motorcycle
Aist | Cross:bicycle | Rocket:bicycle
# ---- Япония
Toyota | Camry:car | Corolla:car,hatchback | RAV4:crossover | Land Cruiser 200:crossover | Land Cruiser 300:crossover | Land Cruiser Prado:crossover | Highlander:crossover | Avensis:car | Yaris:hatchback | Hilux:pickup | C-HR:crossover | Fortuner:crossover | Alphard:van | Vitz:hatchback | Mark II:car | Chaser:car | Supra:sports | Prius:hatchback | Harrier:crossover
Honda | Civic:car,hatchback | Accord:car | CR-V:crossover | Fit:hatchback | Pilot:crossover | HR-V:crossover | Stepwgn:van | Odyssey:van | S2000:convertible | CB400:motorcycle | CBR600RR:motorcycle | CB500X:motorcycle | Africa Twin:motorcycle | Rebel 500:motorcycle | Gold Wing:motorcycle | Dio:scooter | Lead:scooter | Forza:scooter | PCX:scooter
Nissan | Qashqai:crossover | X-Trail:crossover | Almera:car | Juke:crossover | Murano:crossover | Patrol:crossover | Terrano:crossover | Note:hatchback | Teana:car | Skyline:car | Pathfinder:crossover | Navara:pickup | GT-R:sports | Silvia:sports | Serena:van
Mazda | 3:car,hatchback | 6:car | CX-5:crossover | CX-7:crossover | CX-9:crossover | CX-30:crossover | 2:hatchback | MX-5:convertible | Demio:hatchback | RX-8:sports
Mitsubishi | Lancer:car | Outlander:crossover | Pajero:crossover | Pajero Sport:crossover | ASX:crossover | L200:pickup | Eclipse Cross:crossover | Delica:van | Galant:car
Subaru | Forester:crossover | Outback:crossover | Impreza:hatchback,car | XV:crossover | Legacy:car | WRX:car | BRZ:sports
Suzuki | Grand Vitara:crossover | Vitara:crossover | SX4:crossover | Jimny:crossover | Swift:hatchback | Escudo:crossover | GSX-R750:motorcycle | SV650:motorcycle | V-Strom 650:motorcycle | Bandit 400:motorcycle | Boulevard M109R:motorcycle | Address:scooter | Burgman:scooter
Lexus | RX:crossover | NX:crossover | LX:crossover | GX:crossover | ES:car | IS:car | LS:car | UX:crossover
Infiniti | FX:crossover | QX56:crossover | QX60:crossover | QX80:crossover | Q50:car | G35:car | EX:crossover
Acura | MDX:crossover | RDX:crossover | TL:car
Yamaha | MT-07:motorcycle | MT-09:motorcycle | YZF-R1:motorcycle | YZF-R6:motorcycle | FZ6:motorcycle | XT660:motorcycle | Tenere 700:motorcycle | Jog:scooter | Aerox:scooter | Vino:scooter
Kawasaki | Ninja 400:motorcycle | Z650:motorcycle | Z900:motorcycle | Versys 650:motorcycle | Vulcan S:motorcycle | ZZR400:motorcycle
# ---- Корея
Kia | Rio:car,hatchback | Sportage:crossover | Ceed:hatchback | Optima:car | K5:car | Sorento:crossover | Soul:crossover | Cerato:car | Picanto:hatchback | Seltos:crossover | Carnival:van | Mohave:crossover | Stinger:car | Spectra:car
Hyundai | Solaris:car | Creta:crossover | Tucson:crossover | Santa Fe:crossover | Elantra:car | Sonata:car | Accent:car | i30:hatchback | Getz:hatchback | Palisade:crossover | Starex:van | ix35:crossover
Genesis | G70:car | G80:car | GV70:crossover | GV80:crossover
SsangYong | Kyron:crossover | Actyon:crossover | Rexton:crossover | Korando:crossover
# ---- Германия
Volkswagen | Polo:car,hatchback | Golf:hatchback | Tiguan:crossover | Passat:car | Touareg:crossover | Jetta:car | Teramont:crossover | Transporter:van | Caddy:van | Amarok:pickup | Multivan:van | Touran:van
Skoda | Octavia:car,hatchback | Rapid:car | Kodiaq:crossover | Karoq:crossover | Superb:car | Fabia:hatchback | Yeti:crossover | Kamiq:crossover
Mercedes-Benz | C-Class:car | E-Class:car | S-Class:car | GLC:crossover | GLE:crossover | GLS:crossover | G-Class:crossover | A-Class:hatchback | Vito:van | Sprinter:van | CLA:car | ML:crossover | Viano:van
BMW | 3 Series:car | 5 Series:car | 7 Series:car | X1:crossover | X3:crossover | X5:crossover | X6:crossover | X7:crossover | 1 Series:hatchback | Z4:convertible | M3:car | M5:car | R 1250 GS:motorcycle | F 800 GS:motorcycle | S 1000 RR:motorcycle | R nineT:motorcycle
Audi | A3:hatchback | A4:car | A6:car | A8:car | Q3:crossover | Q5:crossover | Q7:crossover | Q8:crossover | TT:sports | RS6:car | A5:car
Opel | Astra:hatchback | Insignia:car | Zafira:van | Corsa:hatchback | Mokka:crossover | Vectra:car | Antara:crossover
Porsche | Cayenne:crossover | Macan:crossover | 911:sports | Panamera:car | Boxster:convertible | Taycan:car
Mini | Cooper:hatchback | Countryman:crossover
# ---- Франция, Италия, Британия, Швеция
Renault | Logan:car | Duster:crossover | Sandero:hatchback | Kaptur:crossover | Arkana:crossover | Megane:hatchback | Fluence:car | Koleos:crossover | Dokker:van | Master:van
Peugeot | 308:hatchback | 408:car | 3008:crossover | 2008:crossover | 206:hatchback | Partner:van | Boxer:van | 5008:crossover
Citroen | C4:hatchback | C5:car | C3:hatchback | Berlingo:van | Jumper:van | C5 Aircross:crossover
Fiat | Ducato:van | Doblo:van | 500:hatchback | Albea:car
Iveco | Daily:van
Volvo | XC60:crossover | XC90:crossover | XC40:crossover | S60:car | S80:car | V70:car
Land Rover | Discovery:crossover | Range Rover:crossover | Range Rover Sport:crossover | Range Rover Evoque:crossover | Defender:crossover | Freelander:crossover
Ducati | Monster:motorcycle | Panigale V4:motorcycle | Multistrada:motorcycle | Scrambler:motorcycle
Aprilia | RS 660:motorcycle | Tuono:motorcycle | SR:scooter
Vespa | Primavera:scooter | Sprint:scooter | GTS:scooter
Piaggio | Liberty:scooter | Zip:scooter | Beverly:scooter
Triumph | Street Triple:motorcycle | Tiger 800:motorcycle | Bonneville:motorcycle
KTM | Duke 390:motorcycle | Duke 790:motorcycle | 1290 Super Adventure:motorcycle | EXC 300:motorcycle
Seat | Leon:hatchback | Ibiza:hatchback | Ateca:crossover
# ---- США
Ford | Focus:hatchback,car | Mondeo:car | Kuga:crossover | Explorer:crossover | Transit:van | Ranger:pickup | Fiesta:hatchback | EcoSport:crossover | Mustang:sports | F-150:pickup
Chevrolet | Niva:crossover | Cruze:car | Lacetti:car,hatchback | Aveo:car,hatchback | Captiva:crossover | Cobalt:car | Tahoe:crossover | Camaro:sports | Spark:hatchback | Lanos:car
Jeep | Grand Cherokee:crossover | Wrangler:crossover | Compass:crossover | Cherokee:crossover | Renegade:crossover
Cadillac | Escalade:crossover | CTS:car | SRX:crossover
Dodge | Ram:pickup | Charger:car | Challenger:sports
Chrysler | 300C:car | Voyager:van
Tesla | Model 3:car | Model Y:crossover | Model S:car | Model X:crossover
Harley-Davidson | Sportster 883:motorcycle | Fat Boy:motorcycle | Street Glide:motorcycle | Iron 883:motorcycle
# ---- Китай
Chery | Tiggo 4:crossover | Tiggo 7 Pro:crossover | Tiggo 8 Pro:crossover | Tiggo 8 Pro Max:crossover | Arrizo 8:car | Tiggo 2:crossover | Amulet:car
Haval | Jolion:crossover | F7:crossover | F7x:crossover | Dargo:crossover | H9:crossover | H5:crossover | M6:crossover
Geely | Coolray:crossover | Atlas:crossover | Tugella:crossover | Monjaro:crossover | Emgrand:car | Okavango:crossover
Exeed | TXL:crossover | LX:crossover | VX:crossover | RX:crossover
Omoda | C5:crossover | S5:car | C7:crossover
Jetour | X70 Plus:crossover | Dashing:crossover | T2:crossover | X90 Plus:crossover
Changan | CS35 Plus:crossover | CS55 Plus:crossover | CS75 Plus:crossover | UNI-K:crossover | UNI-V:car | Alsvin:car
Great Wall | Hover:crossover | Wingle:pickup | Poer:pickup
Belgee | X50:crossover | X70:crossover
Tank | 300:crossover | 500:crossover
Li Auto | L7:crossover | L9:crossover | L6:crossover
Zeekr | 001:car | 007:car | X:crossover
Voyah | Free:crossover | Dream:van | Passion:car
BYD | Song Plus:crossover | Han:car | Seal:car | Tang:crossover | Qin:car
Hongqi | HS5:crossover | H9:car | E-HS9:crossover
JAC | JS6:crossover | T6:pickup | S3:crossover
FAW | Bestune T77:crossover | Bestune T99:crossover
Dongfeng | 580:crossover | Shine Max:crossover | AX7:crossover
Kaiyi | E5:car | X3:crossover
Livan | X3 Pro:crossover | S6 Pro:crossover
Jaecoo | J7:crossover | J8:crossover
BAIC | U5 Plus:car | X35:crossover | BJ40:crossover
Lifan | X60:crossover | Solano:car | Smily:hatchback
CFMOTO | 650NK:motorcycle | 700CL-X:motorcycle | 450SR:motorcycle
Voge | 300 Rally:motorcycle | 500DS:motorcycle
# ---- Мото и вело (остальные)
Racer | Panther:motorcycle | Nitro:motorcycle | Ranger:motorcycle
Regulmoto | Sport-003:motorcycle | ZR:motorcycle
Stels | 600 Benelli:motorcycle | Flex:scooter | Navigator 500:bicycle | Navigator 900:bicycle | Miss 6000:bicycle | Pilot 350:bicycle
Forward | Apache:bicycle | Sporting:bicycle | Dortmund:bicycle | Twister:bicycle
Merida | Big.Nine:bicycle | Scultura:bicycle | Crossway:bicycle | Reacto:bicycle
Giant | Talon:bicycle | Escape:bicycle | TCR:bicycle | ATX:bicycle
Trek | Marlin:bicycle | FX:bicycle | Domane:bicycle | X-Caliber:bicycle
Specialized | Rockhopper:bicycle | Sirrus:bicycle | Allez:bicycle
Cube | Aim:bicycle | Attention:bicycle | Nature:bicycle
Author | Solution:bicycle | Traction:bicycle | Rapid:bicycle
Format | 1213:bicycle | 5342:bicycle
Altair | MTB HT:bicycle | City:bicycle
Cannondale | Trail:bicycle | Topstone:bicycle
Scott | Aspect:bicycle | Sub Cross:bicycle
Shulz | Krabi:bicycle | Goa:bicycle
"""

makes, seen = [], set()
for line in DATA.strip().splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    parts = [p.strip() for p in line.split("|")]
    name, models = parts[0], []
    assert name not in seen, f"дубликат марки {name}"
    seen.add(name)
    mseen = set()
    for chunk in parts[1:]:
        mname, _, bodies = chunk.rpartition(":")
        bodies = [b.strip() for b in bodies.split(",") if b.strip()]
        assert mname, f"{name}: модель без кузова — {chunk}"
        assert mname not in mseen, f"{name}: дубликат модели {mname}"
        mseen.add(mname)
        for b in bodies:
            assert b in S, f"{name} {mname}: неизвестный силуэт {b}"
        model = {"name": mname, "bodies": bodies}
        extra = MODEL_ALIASES.get(f"{name}/{mname}")
        if extra:
            model["aliases"] = extra.split()
        models.append(model)
    make = {"name": name, "models": models}
    ma = MAKE_ALIASES.get(name)
    if ma:
        make["aliases"] = ma.split()
    makes.append(make)

# Пишем компактно вручную: json.dump раскладывает каждый кузов на свою строку
# и раздувает файл вдвое, а его ещё читать глазами в ревью.
lines = ["{", "  \"version\": 2,", "  \"makes\": ["]
for i, mk in enumerate(makes):
    lines.append("    {")
    lines.append("      \"name\": %s," % json.dumps(mk["name"], ensure_ascii=False))
    if mk.get("aliases"):
        lines.append("      \"aliases\": [%s]," %
                     ", ".join(json.dumps(a, ensure_ascii=False) for a in mk["aliases"]))
    lines.append("      \"models\": [")
    for j, m in enumerate(mk["models"]):
        bodies = ", ".join(json.dumps(b) for b in m["bodies"])
        tail = "" if j == len(mk["models"]) - 1 else ","
        al = ""
        if m.get("aliases"):
            al = ", \"aliases\": [%s]" % ", ".join(
                json.dumps(a, ensure_ascii=False) for a in m["aliases"])
        lines.append("        { \"name\": %s, \"bodies\": [%s]%s }%s"
                     % (json.dumps(m["name"], ensure_ascii=False), bodies, al, tail))
    lines.append("      ]")
    lines.append("    }" + ("" if i == len(makes) - 1 else ","))
lines += ["  ]", "}"]

path = "TripTrack/Resources/VehicleCatalog.json"
with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print(f"марок: {len(makes)}   моделей: {sum(len(m['models']) for m in makes)}   →  {path}")
