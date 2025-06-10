document.addEventListener("DOMContentLoaded", () => {
    const eventsList = document.getElementById('eventsList');
    const loading = document.getElementById('loading');
    let skip = window.skip; // Используем данные из глобальной переменной
    let isLoading = false;

    // Функция для загрузки дополнительных мероприятий
    const loadMoreEvents = async () => {
        if (isLoading) return;
        isLoading = true;
        loading.style.display = 'block';

        try {
            console.log('Загрузка новых мероприятий...');
            const response = await fetch(`/events?skip=${skip}&limit=10`, {
                headers: {
                    'X-Requested-With': 'XMLHttpRequest'
                }
            });
            if (!response.ok) {
                throw new Error(`Ошибка HTTP: ${response.status}`);
            }
            const newEvents = await response.json();
            console.log('Получены новые мероприятия:', newEvents);

            if (newEvents.length > 0) {
                newEvents.forEach(event => {
                    const eventDiv = document.createElement('div');
                    eventDiv.className = 'event';
                    eventDiv.innerHTML = `
                        <h2>${event.title}</h2>
                        <p>${event.description}</p>
                        <p><strong>Тип:</strong> ${event.event_type}</p>
                        <p><strong>Цель:</strong> ${event.goal}</p>
                        <p><strong>Уровень сложности:</strong> ${event.difficulty}</p>
                        <p><strong>Начало:</strong> ${event.start_time}</p>
                        <p><strong>Окончание:</strong> ${event.end_time}</p>
                        <p><strong>Максимум участников:</strong> ${event.max_participants}</p>
                        <!-- Блок для отображения свободных мест -->
                    <div class="free-slots">
                        <i class="fas fa-users"></i>
                        <span>Свободные места: <span id="free-slots-${event.id}">${event.available_seats}</span>/${event.max_participants}</span>
                    </div>
                        <p><strong>Публичное:</strong> ${event.is_public ? 'Да' : 'Нет'}</p>
                        <div id="map-${event.id}" class="map"></div>
                        <a href="/events/${event.id}">Подробнее</a>
                        <button class="participate-button" data-event-id="${event.id}">Записаться на мероприятие</button>
                    `;
                    eventsList.appendChild(eventDiv);

                    // Инициализация карты для нового мероприятия
                    const map = L.map(`map-${event.id}`).setView([55.7558, 37.6176], 12);
                    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                    }).addTo(map);

                    if (event.route_points && event.route_points.length > 0) {
                        const routePoints = event.route_points.map(point => [point.latitude, point.longitude]);
                        const polyline = L.polyline(routePoints, { color: 'blue' }).addTo(map);
                        map.fitBounds(polyline.getBounds());
                    }
                });

                skip += newEvents.length;
            } else {
                console.log('Новых мероприятий больше нет.');
            }
        } catch (error) {
            console.error('Ошибка при загрузке мероприятий:', error);
        } finally {
            isLoading = false;
            loading.style.display = 'none';
        }
    };

    // Обработка прокрутки страницы для подгрузки мероприятий
    window.addEventListener('scroll', () => {
        if (window.innerHeight + window.scrollY >= document.body.offsetHeight - 100) {
            loadMoreEvents();
        }
    });

    // Инициализация карт для уже загруженных мероприятий
    const events = window.eventsData; // Используем данные из глобальной переменной
    events.forEach(event => {
        const mapId = `map-${event.id}`;
        const map = L.map(mapId).setView([55.7558, 37.6176], 12);

        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        }).addTo(map);

        if (event.route_points && event.route_points.length > 0) {
            const routePoints = event.route_points.map(point => [point.latitude, point.longitude]);
            const polyline = L.polyline(routePoints, { color: 'blue' }).addTo(map);
            map.fitBounds(polyline.getBounds());
        }
    });

    // Обработка нажатия на кнопку "Записаться на мероприятие"
   document.addEventListener('click', async (e) => {
    if (e.target.classList.contains('participate-button')) {
        const eventId = e.target.getAttribute('data-event-id');
        const loading = document.getElementById('loading');
        loading.style.display = 'block';

        try {
            const response = await fetch(`/events/${eventId}/participate`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': '{{ csrf_token() }}'  // Если используется CSRF-защита
                },
                credentials: 'include'  // Для передачи куки, если требуется авторизация
            });

            if (!response.ok) {
                // Пытаемся получить JSON с сообщением об ошибке
                const errorData = await response.json();
                // Если сервер вернул поле "detail", используем его как сообщение об ошибке
                const errorMessage = errorData.detail || `Ошибка HTTP: ${response.status}`;
                throw new Error(errorMessage);
            }

            const result = await response.json();
            console.log('Заявка подана:', result);
            alert('Вы успешно записаны на мероприятие!');
        } catch (error) {
            console.error('Ошибка при подаче заявки:', error);
            // Отображаем конкретное сообщение об ошибке
            alert(error.message);
        } finally {
            loading.style.display = 'none';
        }
    }
});
});