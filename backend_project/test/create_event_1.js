document.addEventListener("DOMContentLoaded", function () {
    let map;
    let markers = [];
    let polyline; // Синяя линия (прямые отрезки)
    let routeLayer; // Красная линия (маршрут от API)
    let showBlueLine = true; // Флаг для отображения синей линии

    const OPENROUTE_API_KEY = '5b3ce3597851110001cf6248fc87794625ca407fa03a6dac7017f830'; // Ваш API-ключ

    // Получаем элементы для отображения информации о красной линии
    const redDistanceElement = document.getElementById("redDistance");
    const redDurationElement = document.getElementById("redDuration");

    // Получаем элементы для отображения информации о синей линии
    const blueDistanceElement = document.getElementById("blueDistance");
    const blueDurationElement = document.getElementById("blueDuration");

    // Инициализация карты
    function initMap() {
        const mapElement = document.getElementById("map");
        if (!mapElement) {
            console.error("Элемент #map не найден!");
            return;
        }

        map = L.map('map').setView([55.7558, 37.6176], 12); // Центр карты (Москва)

        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        }).addTo(map);

        // Обработка кликов по карте
        map.on('click', function (event) {
            addMarker(event.latlng);
            updatePolyline(); // Обновляем линию при добавлении маркера
        });

        console.log("Карта инициализирована.");
    }

    // Добавление маркера на карту
    function addMarker(location) {
        // Проверяем, есть ли уже маркер в этом месте
        const existingMarker = markers.find(marker => {
            const markerLatLng = marker.getLatLng();
            return markerLatLng.lat === location.lat && markerLatLng.lng === location.lng;
        });

        if (existingMarker) {
            // Если маркер уже существует, удаляем его
            map.removeLayer(existingMarker);
            markers = markers.filter(marker => marker !== existingMarker);
            updatePolyline(); // Обновляем линию
            console.log("Маркер удален:", existingMarker.getLatLng());
        } else {
            // Если маркера нет, добавляем новый
            const marker = L.marker([location.lat, location.lng]).addTo(map);
            markers.push(marker);
            console.log("Добавлен маркер:", marker.getLatLng());

            // Добавляем обработчик для удаления маркера при клике
            marker.on('click', function () {
                map.removeLayer(marker);
                markers = markers.filter(m => m !== marker);
                updatePolyline(); // Обновляем линию
                console.log("Маркер удален:", marker.getLatLng());
            });
        }

        updatePolyline(); // Обновляем линию
    }

    // Обновление синей линии между маркерами
    function updatePolyline() {
        if (polyline) {
            map.removeLayer(polyline); // Удаляем старую линию
        }

        const latlngs = markers.map(marker => marker.getLatLng());
        if (latlngs.length > 1 && showBlueLine) {
            polyline = L.polyline(latlngs, { color: 'blue' }).addTo(map); // Рисуем новую линию
            updateBlueLineInfo(latlngs); // Обновляем данные для синей линии
        } else {
            updateBlueLineInfo(null); // Сбрасываем данные
        }
    }

    // Обновление информации о синей линии
    function updateBlueLineInfo(latlngs) {
        if (latlngs && latlngs.length > 1) {
            const distance = calculateDistance(latlngs).toFixed(2); // Расстояние в км
            const speed = 5; // Скорость 5 км/ч
            const duration = Math.ceil((distance / speed) * 60); // Время в минутах

            blueDistanceElement.textContent = `Расстояние (синяя линия): ${distance} км`;
            blueDurationElement.textContent = `Оценочное время (синяя линия): ${duration} мин`;
        } else {
            blueDistanceElement.textContent = "Расстояние (синяя линия): 0 км";
            blueDurationElement.textContent = "Оценочное время (синяя линия): 0 мин";
        }
    }

    // Расчет расстояния между точками
    function calculateDistance(latlngs) {
        const R = 6371; // Радиус Земли в км
        let totalDistance = 0;

        for (let i = 0; i < latlngs.length - 1; i++) {
            const { lat: lat1, lng: lng1 } = latlngs[i];
            const { lat: lat2, lng: lng2 } = latlngs[i + 1];

            const dLat = ((lat2 - lat1) * Math.PI) / 180;
            const dLng = ((lng2 - lng1) * Math.PI) / 180;

            const a = Math.sin(dLat / 2) ** 2 +
                Math.cos((lat1 * Math.PI) / 180) *
                Math.cos((lat2 * Math.PI) / 180) *
                Math.sin(dLng / 2) ** 2;

            const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
            totalDistance += R * c;
        }

        return totalDistance;
    }

    // Удаление последней точки
    function removeLastMarker() {
        if (markers.length > 0) {
            const lastMarker = markers.pop();
            map.removeLayer(lastMarker);
            updatePolyline(); // Обновляем линию после удаления маркера
            console.log("Удален последний маркер.");
        } else {
            console.log("Нет маркеров для удаления.");
        }
    }

    // Построение маршрута через OpenRouteService
    async function buildRoute() {
        if (markers.length < 2) {
            alert("Добавьте как минимум две точки для построения маршрута.");
            return;
        }

        // Формируем координаты для запроса
        const coordinates = markers.map(marker => {
            const latLng = marker.getLatLng();
            return [latLng.lng, latLng.lat]; // OpenRouteService ожидает [долгота, широта]
        });

        console.log("Coordinates sent to API:", coordinates);

        // Проверяем, включена ли оптимизация маршрута
        const optimizeRoute = document.getElementById("optimizeRoute").checked;

        // Тело запроса
        const requestBody = {
            coordinates: coordinates,
            elevation: true, // Учитывать высоту

        };

        /*if (optimizeRoute) {
            requestBody.round_trip = {
                length: 0, // Полная длина маршрута
                points: coordinates.length, // Количество точек для оптимизации
            };
        }*/

        try {
            // Запрос к API OpenRouteService
            const response = await fetch(`https://api.openrouteservice.org/v2/directions/foot-walking/geojson?timestamp=${Date.now()}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': OPENROUTE_API_KEY,
                },
                body: JSON.stringify(requestBody),
            });

            if (!response.ok) {
                const errorData = await response.json();
                console.error("Ошибка при построении маршрута:", errorData);
                alert(`Ошибка при построении маршрута: ${errorData.error.message || "Неизвестная ошибка"}`);
                return;
            }

            const data = await response.json();

            if (data.features && data.features.length > 0) {
                // Удаляем старый маршрут, если он есть
                if (routeLayer) {
                    map.removeLayer(routeLayer);
                }

                // Отображаем маршрут на карте
                const route = data.features[0];
                routeLayer = L.geoJSON(route, {
                    style: { color: 'red', weight: 4 }, // Стиль линии маршрута
                }).addTo(map);
                console.log("Data:", data);
                console.log("Маршрут построен:", route);
                updateRouteInfo(route); // Обновляем информацию о маршруте
            } else {
                alert("Не удалось построить маршрут. Проверьте точки и попробуйте снова.");
            }
        } catch (error) {
            console.error("Ошибка при выполнении запроса:", error);
            alert("Произошла ошибка при выполнении запроса. Проверьте консоль для подробностей.");
        }

        // Обновляем информацию о синей линии после построения маршрута
        const latlngs = markers.map(marker => marker.getLatLng());
        updateBlueLineInfo(latlngs);
    }

    // Обновление информации о маршруте (красная линия)
    function updateRouteInfo(route) {
        if (route && route.properties && route.properties.segments) {
            const segments = route.properties.segments;

            // Суммируем расстояние и время всех сегментов
            const totalDistance = segments.reduce((sum, seg) => sum + seg.distance, 0);
            const totalDuration = segments.reduce((sum, seg) => sum + seg.duration, 0);

            // Форматирование
            const distanceKm = (totalDistance / 1000).toFixed(2); // км
            const durationMin = Math.ceil(totalDuration / 60);    // мин

            // Логирование и отображение
            console.log(`Суммарное расстояние: ${distanceKm} км`);
            console.log(`Суммарное время: ${durationMin} мин`);
            redDistanceElement.textContent = `Расстояние (красная линия): ${distanceKm} км`;
            redDurationElement.textContent = `Оценочное время (красная линия): ${durationMin} мин`;
        } else {
            console.error("Данные маршрута некорректны или отсутствуют.");
        }
    }

    // Переключение синей линии
    function toggleBlueLine() {
        showBlueLine = !showBlueLine;
        updatePolyline(); // Обновляем линию
        const toggleButton = document.getElementById("toggleBlueLine");
        toggleButton.textContent = showBlueLine ? "Скрыть синюю линию" : "Показать синюю линию";
    }

    // Очистка карты
    function clearMap() {
        markers.forEach(marker => map.removeLayer(marker));
        markers = [];
        if (polyline) map.removeLayer(polyline);
        if (routeLayer) map.removeLayer(routeLayer);
        updateBlueLineInfo(null); // Сброс информации
    }

    // Обработчики кнопок
    const removeLastPointButton = document.getElementById("removeLastPoint");
    if (removeLastPointButton) {
        removeLastPointButton.addEventListener("click", removeLastMarker);
    } else {
        console.error("Кнопка #removeLastPoint не найдена!");
    }

    const buildRouteButton = document.getElementById("buildRoute");
    if (buildRouteButton) {
        buildRouteButton.addEventListener("click", buildRoute);
    } else {
        console.error("Кнопка #buildRoute не найдена!");
    }

    const toggleBlueLineButton = document.getElementById("toggleBlueLine");
    if (toggleBlueLineButton) {
        toggleBlueLineButton.addEventListener("click", toggleBlueLine);
    } else {
        console.error("Кнопка #toggleBlueLine не найдена!");
    }

    const clearMapButton = document.getElementById("clearMap");
    if (clearMapButton) {
        clearMapButton.addEventListener("click", clearMap);
    } else {
        console.error("Кнопка #clearMap не найдена!");
    }

    // Находим форму и добавляем обработчик события
    const eventForm = document.getElementById("eventForm");
    if (eventForm) {
        eventForm.addEventListener("submit", async (event) => {
            event.preventDefault();

            // Сбор данных о маркерах (пользовательский маршрут)
            const userRoutePoints = markers.map((marker) => ({
                latitude: marker.getLatLng().lat,
                longitude: marker.getLatLng().lng,
                name: "",  // Можно добавить поле для названия точки
                timestamp: new Date().toISOString().slice(0, -1), // Убираем 'Z'
            }));

            // Сбор данных о маршруте, построенном через API
            const apiRoute = routeLayer ? routeLayer.toGeoJSON() : null;

            // Определяем, какой маршрут сохранять
            let routePointsToSave;
            if (apiRoute) {
                // Если есть маршрут от API, спрашиваем пользователя
                const saveApiRoute = confirm("Хотите сохранить маршрут, построенный через API?");
                if (saveApiRoute) {
                    // Сохраняем маршрут от API
                    routePointsToSave = apiRoute.features[0].geometry.coordinates.map(coord => ({
                        latitude: coord[1],
                        longitude: coord[0],
                        name: "",
                        timestamp: new Date().toISOString().slice(0, -1),
                    }));
                    console.log("Пользователь выбрал маршрут от API.");
                } else {
                    // Сохраняем пользовательский маршрут
                    routePointsToSave = userRoutePoints;
                    console.log("Пользователь выбрал пользовательский маршрут.");
                }
            } else {
                // Если маршрут от API не построен, сохраняем пользовательский
                routePointsToSave = userRoutePoints;
                console.log("Маршрут от API не построен. Сохранен пользовательский маршрут.");
            }

            // Сбор данных формы
            const formData = {
                title: document.getElementById("title").value,
                description: document.getElementById("description").value,
                event_type: document.getElementById("event_type").value.toUpperCase(),
                goal: document.getElementById("goal").value,
                start_time: new Date(document.getElementById("start_time").value).toISOString().slice(0, -1),
                end_time: new Date(document.getElementById("end_time").value).toISOString().slice(0, -1),
                difficulty: document.getElementById("difficulty").value,
                max_participants: parseInt(document.getElementById("max_participants").value),
                is_public: document.getElementById("is_public").checked,
                route_points: routePointsToSave, // Сохраняем выбранный маршрут
            };

            // Логирование данных перед отправкой
            console.log("Отправляемые данные:", JSON.stringify(formData, null, 2));

            try {
                // Отправка данных на сервер
                const response = await fetch("/events/create", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify(formData),
                });

                if (!response.ok) {
                    // Если ответ не успешный, выводим подробности ошибки
                    const errorData = await response.json();
                    const errorMessage = JSON.stringify(errorData, null, 2);
                    alert(`Ошибка при создании мероприятия:\n${errorMessage}`);
                    return;
                }

                // Если всё успешно
                alert("Мероприятие создано!");
                window.location.href = "/events";
            } catch (error) {
                console.error("Ошибка при выполнении запроса:", error);
                alert("Произошла ошибка при выполнении запроса. Проверьте консоль для подробностей.");
            }
        });
    } else {
        console.error("Форма #eventForm не найдена!");
    }

    // Инициализация карты после загрузки страницы
    initMap();
});