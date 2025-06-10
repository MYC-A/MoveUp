// Глобальные переменные
let followersSkip = 0;
let followingSkip = 0;
let eventsSkip = 0;
let applicationsSkip = 0;
const limit = 10;
let currentEventId = null;

// Загрузка заявок для конкретного мероприятия
const loadApplicationsForEvent = async (eventId) => {
    currentEventId = eventId; // Сохраняем ID текущего мероприятия
    applicationsSkip = 0; // Сбрасываем skip
    document.getElementById('applicationsList').innerHTML = ''; // Очищаем список
    document.getElementById('loadMoreApplications').style.display = 'block'; // Показываем кнопку
    await loadApplications(); // Загружаем данные

    // Переключаем содержимое модального окна
    document.getElementById('eventsContent').style.display = 'none'; // Скрываем мероприятия
    document.getElementById('applicationsContent').style.display = 'block'; // Показываем заявки
    document.getElementById('modalTitle').textContent = 'Заявки на мероприятие'; // Меняем заголовок
};

// Возврат к списку мероприятий
const backToEvents = () => {
    document.getElementById('eventsContent').style.display = 'block'; // Показываем мероприятия
    document.getElementById('applicationsContent').style.display = 'none'; // Скрываем заявки
    document.getElementById('modalTitle').textContent = 'Мои мероприятия'; // Возвращаем заголовок
};

// Загрузка заявок
const loadApplications = async () => {
    try {
        const response = await fetch(`/profile/event/${currentEventId}/applications?skip=${applicationsSkip}&limit=${limit}`, {
            credentials: 'include',
            cache: 'no-cache' // Отключаем кэширование
        });
        if (response.ok) {
            const data = await response.json();
            const applicationsList = document.getElementById('applicationsList');

            data.applications.forEach(app => {
                const listItem = document.createElement('li');
                listItem.id = `application-${app.id}`; // Уникальный ID для заявки
                listItem.classList.add('list-group-item');
                listItem.innerHTML = `
                    <div class="d-flex justify-content-between align-items-center">
                        <div>
                            <img src="${app.user_avatar || '/static/images/default-avatar.png'}" alt="${app.user_name}" class="rounded-circle me-2" width="30" height="30">
                            <a href="/profile/view/${app.user_id}" class="text-decoration-none">${app.user_name}</a>
                        </div>
                        <div>
                            <button class="btn btn-success btn-sm approve-btn" data-participant-id="${app.id}" data-event-id="${currentEventId}">✓</button>
                            <button class="btn btn-danger btn-sm ms-2 reject-btn" data-participant-id="${app.id}" data-event-id="${currentEventId}">✗</button>
                        </div>
                    </div>
                `;
                applicationsList.appendChild(listItem);
            });

            // Увеличиваем skip для следующей загрузки
            applicationsSkip += limit;

            // Скрываем кнопку "Загрузить еще", если больше нет данных
            if (data.applications.length < limit) {
                document.getElementById('loadMoreApplications').style.display = 'none';
            }
        } else {
            console.error('Ошибка загрузки заявок:', await response.text());
        }
    } catch (error) {
        console.error('Ошибка при загрузке заявок:', error);
    }
};

// Одобрение заявки
const approveApplication = async (participantId, eventId) => {
    try {
        const response = await fetch(`/profile/event/${eventId}/applications/${participantId}/approve`, {
            method: 'POST',
            credentials: 'include',
            cache: 'no-cache' // Отключаем кэширование
        });
        if (response.ok) {
            alert('Заявка одобрена');
            // Удаляем заявку из DOM
            const applicationElement = document.getElementById(`application-${participantId}`);
            if (applicationElement) {
                console.log('Элемент найден, удаляем:', applicationElement);
                applicationElement.remove();
            } else {
                console.log('Элемент не найден');
            }
        } else {
            const errorText = await response.text();
            console.error('Ошибка одобрения заявки:', errorText);
            alert('Ошибка: ' + errorText);
        }
    } catch (error) {
        console.error('Ошибка при одобрении заявки:', error);
    }
};

// Отклонение заявки
const rejectApplication = async (participantId, eventId) => {
    try {
        const response = await fetch(`/profile/event/${eventId}/applications/${participantId}/reject`, {
            method: 'POST',
            credentials: 'include',
            cache: 'no-cache' // Отключаем кэширование
        });
        if (response.ok) {
            alert('Заявка отклонена');
            // Удаляем заявку из DOM
            const applicationElement = document.getElementById(`application-${participantId}`);
            if (applicationElement) {
                console.log('Элемент найден, удаляем:', applicationElement);
                applicationElement.remove();
            } else {
                console.log('Элемент не найден');
            }
        } else {
            const errorText = await response.text();
            console.error('Ошибка отклонения заявки:', errorText);
            alert('Ошибка: ' + errorText);
        }
    } catch (error) {
        console.error('Ошибка при отклонении заявки:', error);
    }
};

document.addEventListener('DOMContentLoaded', async () => {
    // Загрузка данных профиля
    const loadProfile = async () => {
        try {
            const response = await fetch('/profile', {
                credentials: 'include'
            });
            if (response.ok) {
                const user = await response.json();
                document.getElementById('fullName').textContent = user.full_name;
                document.getElementById('bio').textContent = user.bio || "Нет биографии";
                document.getElementById('avatar').src = user.avatar_url || "/static/images/default-avatar.png";
                document.getElementById('fullNameInput').value = user.full_name;
                document.getElementById('bioInput').value = user.bio || "";
            } else {
                console.error('Ошибка загрузки профиля:', await response.text());
            }
        } catch (error) {
            console.error('Ошибка при загрузке профиля:', error);
        }
    };

    // Загрузка статистики активности
    const loadStats = async () => {
        try {
            const response = await fetch('/profile/stats', {
                credentials: 'include'
            });
            if (response.ok) {
                const stats = await response.json();
                document.getElementById('postCount').textContent = stats.posts_count;
                document.getElementById('commentCount').textContent = stats.comments_count;
                document.getElementById('likeCount').textContent = stats.likes_count;
            } else {
                console.error('Ошибка загрузки статистики:', await response.text());
            }
        } catch (error) {
            console.error('Ошибка при загрузке статистики:', error);
        }
    };

    // Загрузка подписчиков
    const loadFollowers = async () => {
        try {
            const response = await fetch(`/profile/followers?skip=${followersSkip}&limit=${limit}`, {
                credentials: 'include'
            });
            if (response.ok) {
                const data = await response.json();
                const followersList = document.getElementById('followersList');

                data.followers.forEach(follower => {
                    const listItem = document.createElement('li');
                    listItem.classList.add('list-group-item');
                    listItem.innerHTML = `
                        <a href="/profile/view/${follower.id}" class="text-decoration-none">
                            <img src="${follower.avatar_url || '/static/images/default-avatar.png'}" alt="${follower.full_name}" class="rounded-circle me-2" width="30" height="30">
                            ${follower.full_name}
                        </a>
                    `;
                    followersList.appendChild(listItem);
                });

                // Обновляем счетчик подписчиков
                document.getElementById('followersCount').textContent = data.total_followers;

                // Увеличиваем skip для следующей загрузки
                followersSkip += limit;

                // Скрываем кнопку "Загрузить еще", если больше нет данных
                if (data.followers.length < limit) {
                    document.getElementById('loadMoreFollowers').style.display = 'none';
                }
            } else {
                console.error('Ошибка загрузки подписчиков:', await response.text());
            }
        } catch (error) {
            console.error('Ошибка при загрузке подписчиков:', error);
        }
    };

    // Загрузка подписок
    const loadFollowing = async () => {
        try {
            const response = await fetch(`/profile/following?skip=${followingSkip}&limit=${limit}`, {
                credentials: 'include'
            });
            if (response.ok) {
                const data = await response.json();
                const followingList = document.getElementById('followingList');
                followingList.innerHTML = ''; // Очищаем список перед добавлением новых данных

                if (data.following && Array.isArray(data.following)) {
                    data.following.forEach(follow => {
                        const listItem = document.createElement('li');
                        listItem.classList.add('list-group-item');
                        listItem.innerHTML = `
                            <a href="/profile/view/${follow.id}" class="text-decoration-none">
                                <img src="${follow.avatar_url || '/static/images/default-avatar.png'}" alt="${follow.full_name}" class="rounded-circle me-2" width="30" height="30">
                                ${follow.full_name}
                            </a>
                        `;
                        followingList.appendChild(listItem);
                    });

                    // Обновляем счетчик подписок
                    document.getElementById('followingCount').textContent = data.total_following || data.following.length;

                    // Увеличиваем skip для следующей загрузки
                    followingSkip += limit;

                    // Скрываем кнопку "Загрузить еще", если больше нет данных
                    if (data.following.length < limit) {
                        document.getElementById('loadMoreFollowing').style.display = 'none';
                    }
                } else {
                    console.error('Ошибка: data.following не является массивом', data.following);
                }
            } else {
                console.error('Ошибка загрузки подписок:', await response.text());
            }
        } catch (error) {
            console.error('Ошибка при загрузке подписок:', error);
        }
    };

    // Загрузка мероприятий текущего пользователя
    const loadEvents = async () => {
        try {
            const response = await fetch(`/profile/events?skip=${eventsSkip}&limit=${limit}`, {
                credentials: 'include'
            });
            if (response.ok) {
                const data = await response.json();
                const eventsList = document.getElementById('eventsList');

                data.events.forEach(event => {
                    const listItem = document.createElement('li');
                    listItem.classList.add('list-group-item');
                    listItem.innerHTML = `
                        <div class="d-flex justify-content-between align-items-center">
                            <span>${event.title}</span>
                            <button class="btn btn-sm btn-primary show-applications-btn" data-event-id="${event.id}">
                                Показать заявки
                            </button>
                        </div>
                    `;
                    eventsList.appendChild(listItem);
                });

                // Увеличиваем skip для следующей загрузки
                eventsSkip += limit;

                // Скрываем кнопку "Загрузить еще", если больше нет данных
                if (data.events.length < limit) {
                    document.getElementById('loadMoreEvents').style.display = 'none';
                }
            } else {
                console.error('Ошибка загрузки мероприятий:', await response.text());
            }
        } catch (error) {
            console.error('Ошибка при загрузке мероприятий:', error);
        }
    };

    // Обработчик для кнопки "Загрузить еще" (подписчики)
    document.getElementById('loadMoreFollowers').addEventListener('click', loadFollowers);

    // Обработчик для кнопки "Загрузить еще" (подписки)
    document.getElementById('loadMoreFollowing').addEventListener('click', loadFollowing);

    // Обработчик для кнопки "Загрузить еще" (мероприятия)
    document.getElementById('loadMoreEvents').addEventListener('click', loadEvents);

    // Обработчик для кнопки "Загрузить еще" (заявки)
    document.getElementById('loadMoreApplications').addEventListener('click', loadApplications);

    // Обработчик для кнопки "Назад к мероприятиям"
    document.getElementById('backToEvents').addEventListener('click', backToEvents);

    // Обработчик для открытия модального окна подписчиков
    document.getElementById('showFollowers').addEventListener('click', async () => {
        followersSkip = 0; // Сбрасываем skip
        document.getElementById('followersList').innerHTML = ''; // Очищаем список
        document.getElementById('loadMoreFollowers').style.display = 'block'; // Показываем кнопку
        await loadFollowers(); // Загружаем данные
    });

    // Обработчик для открытия модального окна подписок
    document.getElementById('showFollowing').addEventListener('click', async () => {
        followingSkip = 0; // Сбрасываем skip
        document.getElementById('followingList').innerHTML = ''; // Очищаем список
        document.getElementById('loadMoreFollowing').style.display = 'block'; // Показываем кнопку
        await loadFollowing(); // Загружаем данные
    });

    // Обработчик для открытия модального окна мероприятий
    document.getElementById('showEvents').addEventListener('click', async () => {
        eventsSkip = 0; // Сбрасываем skip
        document.getElementById('eventsList').innerHTML = ''; // Очищаем список
        document.getElementById('loadMoreEvents').style.display = 'block'; // Показываем кнопку
        await loadEvents(); // Загружаем данные
    });

    // Обновление профиля
    document.getElementById('editProfileForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const formData = new FormData(e.target);

        // Добавляем файл аватарки, если он выбран
        const avatarInput = document.getElementById('avatarInput');
        if (avatarInput.files[0]) {
            formData.append('avatar', avatarInput.files[0]);
        }

        try {
            const response = await fetch('/profile', {
                method: 'PUT',
                credentials: 'include',
                body: formData  // Используем FormData для отправки файла
            });

            if (response.ok) {
                alert('Профиль успешно обновлен');
                await loadProfile();
            } else {
                console.error('Ошибка обновления профиля:', await response.text());
            }
        } catch (error) {
            console.error('Ошибка при обновлении профиля:', error);
        }
    });

    // Делегирование событий для кнопок "Показать заявки", "Одобрить" и "Отклонить"
    document.addEventListener('click', async (event) => {
        if (event.target.classList.contains('show-applications-btn')) {
            const eventId = event.target.getAttribute('data-event-id');
            await loadApplicationsForEvent(eventId);
        } else if (event.target.classList.contains('approve-btn')) {
            const participantId = event.target.getAttribute('data-participant-id');
            const eventId = event.target.getAttribute('data-event-id');
            await approveApplication(participantId, eventId);
        } else if (event.target.classList.contains('reject-btn')) {
            const participantId = event.target.getAttribute('data-participant-id');
            const eventId = event.target.getAttribute('data-event-id');
            await rejectApplication(participantId, eventId);
        }
    });

    // Загрузка всех данных
    await loadProfile();
    await loadStats();
});