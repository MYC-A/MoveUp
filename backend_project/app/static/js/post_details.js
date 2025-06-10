let isLoadingComments = false; // Флаг для предотвращения дублирования запросов
let allCommentsLoaded = false; // Флаг для остановки загрузки, если все комментарии загружены
let currentUserId = null; // ID текущего пользователя
let postSocket = null; // WebSocket для обновлений поста
let currentPhotoIndex = 0; // Текущий индекс фотографии
let photoUrls = []; // Массив URL фотографий

document.addEventListener('DOMContentLoaded', async () => {
    const postId = new URLSearchParams(window.location.search).get('post_id');
    if (!postId) {
        console.error('Post ID is missing');
        return;
    }

    // Получаем ID текущего пользователя
    const userResponse = await fetch('/auth/current_user', { credentials: 'include' });
    if (userResponse.ok) {
        const userData = await userResponse.json();
        currentUserId = userData; // Исправлено: сохраняем ID текущего пользователя
    }
    console.log("ID:", currentUserId);

    await loadPost(postId);
    await loadComments(postId);

    // Инициализация WebSocket для обновления комментариев и лайков в реальном времени
    postSocket = new WebSocket(`ws://${window.location.host}/post/ws/post/${postId}`);

    postSocket.onopen = function (event) {
        console.log("WebSocket соединение для поста установлено");
    };

    postSocket.onerror = function (error) {
        console.error("WebSocket для поста ошибка:", error);
    };

    postSocket.onclose = function (event) {
        console.log("WebSocket соединение для поста закрыто");
    };

    postSocket.onmessage = function (event) {
        const update = JSON.parse(event.data);

        if (update.type === "comment" && update.post_id === parseInt(postId)) {
            // Проверяем, что комментарий не от текущего пользователя
            if (update.comment.user_id !== currentUserId) {
                const commentsContainer = document.getElementById('commentsContainer');

                // Добавляем новый комментарий в конец списка
                const commentElement = document.createElement('div');
                commentElement.classList.add('comment');
                commentElement.innerHTML = `
                    <span class="comment-author">${update.comment.user.username}:</span>
                    <span class="comment-content">${update.comment.content}</span>
                `;
                commentsContainer.appendChild(commentElement);

                // Обновляем счетчик комментариев
                const commentsCount = document.querySelector('.post-stats span:nth-child(2)');
                const currentCount = parseInt(commentsCount.textContent.replace("Комментариев: ", ""), 10);
                commentsCount.textContent = `Комментариев: ${currentCount + 1}`;

                // Прокручиваем страницу к новому комментарию
                commentElement.scrollIntoView({ behavior: 'smooth' });
            }
        } else if (update.type === "like" && update.post_id === parseInt(postId)) {
            // Обновляем количество лайков
            const likesCount = document.querySelector('.post-stats span:nth-child(1)');
            likesCount.textContent = `Лайков: ${update.likes_count}`;

            // Обновляем состояние кнопки лайка
            const likeButton = document.querySelector('.like-button');
            if (update.user_id === currentUserId) {
                likeButton.classList.toggle('liked', update.liked);
            }
        }
    };

    // Обработчик для отправки комментария
    const submitCommentButton = document.getElementById('submitComment');
    submitCommentButton.addEventListener('click', async () => {
        const commentInput = document.getElementById('commentInput');
        const commentText = commentInput.value.trim();

        if (!commentText) {
            alert('Комментарий не может быть пустым');
            return;
        }

        await submitComment(postId, commentText);
        commentInput.value = ''; // Очищаем поле ввода
    });

    // Инициализация IntersectionObserver для подгрузки комментариев
    const observer = new IntersectionObserver(
        (entries) => {
            if (entries[0].isIntersecting && !isLoadingComments && !allCommentsLoaded) {
                loadMoreComments(postId);
            }
        },
        { threshold: 0.1 } // Срабатывает, когда 10% последнего комментария видно
    );

    // Наблюдаем за последним комментарием
    const commentsContainer = document.getElementById('commentsContainer');
    if (commentsContainer.lastChild) {
        observer.observe(commentsContainer.lastChild);
    }

    // Обработчик для кнопки "Назад"
    const backButton = document.getElementById('backButton');
    if (backButton) {
        backButton.addEventListener('click', () => {
            const urlParams = new URLSearchParams(window.location.search);
            const source = urlParams.get('source');
            console.log(source);

            if (source === 'profile') {
                // Возвращаемся на страницу профиля
                const userId = urlParams.get('user_id'); // Получаем user_id из URL
                if (userId) {
                    console.log(currentUserId);
                    window.location.href = `/profile/view/${userId}`;
                } else {
                    console.error('User ID is missing');
                }
            } else if (source === 'feed') {
                // Возвращаемся на ленту
                window.location.href = '/post/feed';
            } else {
                // Если источник неизвестен, просто возвращаемся назад
                window.history.back();
            }
        });
    }
});

async function submitComment(postId, commentText) {
    try {
        const response = await fetch(`/post/posts/${postId}/create_comment`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            credentials: 'include',
            body: JSON.stringify({ content: commentText })
        });

        if (response.ok) {
            // Добавляем комментарий в DOM
            const commentsContainer = document.getElementById('commentsContainer');
            const commentElement = document.createElement('div');
            commentElement.classList.add('comment');
            commentElement.innerHTML = `
                <span class="comment-author">Вы:</span>
                <span class="comment-content">${commentText}</span>
            `;
            commentsContainer.appendChild(commentElement);

            // Обновляем счетчик комментариев
            const commentsCount = document.querySelector('.post-stats span:nth-child(2)');
            const currentCount = parseInt(commentsCount.textContent.replace("Комментариев: ", ""), 10);
            commentsCount.textContent = `Комментариев: ${currentCount + 1}`;

            // Прокручиваем страницу к новому комментарию
            commentElement.scrollIntoView({ behavior: 'smooth' });

            // Очищаем поле ввода
            const commentInput = document.getElementById('commentInput');
            commentInput.value = '';
        } else {
            console.error('Ошибка при отправке комментария:', await response.json());
        }
    } catch (error) {
        console.error('Ошибка:', error);
    }
}

async function loadPost(postId) {
    try {
        const response = await fetch(`/post/posts/${postId}/details`, {
            credentials: 'include'
        });

        if (response.status === 401) {
            window.location.href = '/auth';
            return;
        }

        if (!response.ok) {
            throw new Error(`Ошибка HTTP: ${response.status}`);
        }

        const postData = await response.json();
        const postContainer = document.getElementById('postContainer');
        postContainer.innerHTML = `
            <div class="post-header">
                <a href="/profile/view/${postData.post.user.id}" class="post-author">${postData.post.user.full_name}</a>
                <span class="post-time">${new Date(postData.post.created_at).toLocaleString()}</span>
            </div>
            <div class="post-map" id="map-${postData.post.id}"></div>
            <div class="photo-grid-container">
                <div class="photo-grid">
                    ${postData.post.photo_urls.map(url => `
                        <div class="photo-grid-item" data-photo-url="${url}">
                            <img src="${url}" alt="Фото поста" class="post-photo">
                        </div>
                    `).join('')}
                </div>
            </div>
            <div class="post-description">${postData.post.content}</div>
            <div class="post-stats">
                <span>Лайков: ${postData.post.likes_count}</span>
                <span>Комментариев: ${postData.post.comments_count}</span>
            </div>
            <button class="like-button ${postData.post.liked_by_current_user ? 'liked' : ''}" data-post-id="${postData.post.id}">Лайк</button>
        `;

        // Инициализация карты
        initMap(postData.post.id, postData.post.route_data);

        // Добавляем обработчики для фотографий
        document.querySelectorAll('.photo-grid-item').forEach((item, index) => {
            item.addEventListener('click', () => {
                photoUrls = postData.post.photo_urls;
                currentPhotoIndex = index;
                openModal(photoUrls[currentPhotoIndex]);
            });
        });

        // Добавляем обработчик для кнопки лайка
        const likeButton = postContainer.querySelector('.like-button');
        likeButton.addEventListener('click', async () => {
            await likePost(postId, postContainer);
        });
    } catch (error) {
        console.error('Ошибка загрузки поста:', error);
    }
}

// Функция для открытия модального окна
function openModal(photoUrl) {
    const modal = document.getElementById('photo-modal');
    const modalImg = document.getElementById('modal-photo');
    modal.style.display = 'flex';
    modalImg.src = photoUrl;
}

// Закрытие модального окна
document.querySelector('.close-modal').addEventListener('click', () => {
    const modal = document.getElementById('photo-modal');
    modal.style.display = 'none';
});

// Листание фотографий вперед
document.querySelector('.next-button').addEventListener('click', () => {
    currentPhotoIndex = (currentPhotoIndex + 1) % photoUrls.length;
    document.getElementById('modal-photo').src = photoUrls[currentPhotoIndex];
});

// Листание фотографий назад
document.querySelector('.prev-button').addEventListener('click', () => {
    currentPhotoIndex = (currentPhotoIndex - 1 + photoUrls.length) % photoUrls.length;
    document.getElementById('modal-photo').src = photoUrls[currentPhotoIndex];
});

async function loadComments(postId, skip = 0, limit = 10) {
    try {
        isLoadingComments = true;

        // Показываем индикатор загрузки
        const commentsContainer = document.getElementById('commentsContainer');
        const loader = document.createElement('div');
        loader.className = 'loader';
        loader.textContent = 'Загрузка...';
        commentsContainer.appendChild(loader);

        const response = await fetch(`/post/posts/${postId}/comments?skip=${skip}&limit=${limit}`, {
            credentials: 'include'
        });

        if (response.status === 401) {
            window.location.href = '/auth';
            return;
        }

        if (!response.ok) {
            throw new Error(`Ошибка HTTP: ${response.status}`);
        }

        const comments = await response.json();

        // Убираем индикатор загрузки
        commentsContainer.removeChild(loader);

        if (comments.length === 0) {
            allCommentsLoaded = true; // Останавливаем загрузку, если комментариев больше нет
            return;
        }

        comments.forEach(comment => {
            const commentElement = document.createElement('div');
            commentElement.classList.add('comment');
            commentElement.innerHTML = `
                <span class="comment-author">${comment.user.username}:</span>
                <span class="comment-content">${comment.content}</span>
            `;
            commentsContainer.appendChild(commentElement);
        });

        // Наблюдаем за последним комментарием
        const observer = new IntersectionObserver(
            (entries) => {
                if (entries[0].isIntersecting && !isLoadingComments && !allCommentsLoaded) {
                    loadMoreComments(postId);
                }
            },
            { threshold: 0.1 }
        );

        if (commentsContainer.lastChild) {
            observer.observe(commentsContainer.lastChild);
        }
    } catch (error) {
        console.error('Ошибка загрузки комментариев:', error);
    } finally {
        isLoadingComments = false;
    }
}

async function loadMoreComments(postId) {
    const commentsContainer = document.getElementById('commentsContainer');
    const skip = commentsContainer.children.length;
    await loadComments(postId, skip);
}

async function likePost(postId, postElement) {
    try {
        const response = await fetch(`/post/posts/${postId}/like`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            credentials: 'include'
        });

        if (response.ok) {
            const result = await response.json();
            const likesCount = postElement.querySelector('.post-stats span');
            likesCount.textContent = `Лайков: ${result.likes_count}`;

            // Обновляем стиль кнопки лайка
            const likeButton = postElement.querySelector('.like-button');
            likeButton.classList.toggle('liked', result.liked);
        } else if (response.status === 401) {
            window.location.href = '/auth';
        } else {
            console.error('Ошибка при лайке:', await response.json());
        }
    } catch (error) {
        console.error('Ошибка:', error);
    }
}

function initMap(postId, routeData) {
    const map = L.map(`map-${postId}`).setView([routeData[0].latitude, routeData[0].longitude], 13);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap contributors'
    }).addTo(map);

    const routePoints = routeData.map(point => [point.latitude, point.longitude]);
    L.polyline(routePoints, { color: 'blue' }).addTo(map);
}