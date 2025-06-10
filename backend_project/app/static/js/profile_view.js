// Подключение к WebSocket
const feedSocket = new WebSocket(`ws://${window.location.host}/post/ws/feed`);

feedSocket.onopen = function(event) {
    console.log("WebSocket соединение установлено");
};

feedSocket.onerror = function(error) {
    console.error("WebSocket ошибка:", error);
};

feedSocket.onclose = function(event) {
    console.log("WebSocket соединение закрыто");
};

feedSocket.onmessage = function(event) {
    const update = JSON.parse(event.data);

    if (update.type === "like") {
        const postElement = document.querySelector(`.post[data-post-id="${update.post_id}"]`);
        if (postElement) {
            const likesCount = postElement.querySelector('.post-stats span');
            likesCount.textContent = `Лайков: ${update.likes_count}`;

            // Обновляем кнопку лайка только для текущего пользователя
            const likeButton = postElement.querySelector('.like-button');
            if (update.user_id === currentUserId) {  // currentUserId должен быть доступен на клиенте
                if (update.liked) {
                    likeButton.classList.add('liked');
                } else {
                    likeButton.classList.remove('liked');
                }
            }
        }
    } else if (update.type === "comment") {
        const postElement = document.querySelector(`.post[data-post-id="${update.post_id}"]`);
        if (postElement) {
            const commentsContainer = postElement.querySelector('.comments-container');
            const commentElement = document.createElement('div');
            commentElement.classList.add('comment');
            commentElement.innerHTML = `
                <span class="comment-author">${update.comment.user.username}:</span>
                <span class="comment-content">${update.comment.content}</span>
            `;
            commentsContainer.appendChild(commentElement);

            // Обновляем счетчик комментариев
            const commentsCount = postElement.querySelector('.post-stats span:nth-child(2)');
            const currentCount = parseInt(commentsCount.textContent.replace("Комментариев: ", ""), 10);
            commentsCount.textContent = `Комментариев: ${currentCount + 1}`;
        }
    }
};

document.addEventListener('DOMContentLoaded', async () => {
    const userPostsContainer = document.getElementById('userPosts');
    const loadMoreButton = document.getElementById('loadMorePosts');
    const followButton = document.getElementById('followButton');
    let skip = 0;
    const limit = 5; // Количество постов, загружаемых за один раз

    // Функция для загрузки постов
    const loadPosts = async () => {
    const userId = window.location.pathname.split('/').pop();
    const response = await fetch(`/profile/${userId}/posts?skip=${skip}&limit=${limit}`);
    if (response.ok) {
        const posts = await response.json();
        if (posts.length > 0) {
            posts.forEach(post => {
                const postElement = document.createElement('div');
                postElement.classList.add('post');
                postElement.setAttribute('data-post-id', post.id);
                postElement.innerHTML = `
                    <div class="post-header">
                        <span class="post-author">${post.user.full_name}</span>
                        <span class="post-time">${new Date(post.created_at).toLocaleString()}</span>
                    </div>
                    <div class="post-map" id="map-${post.id}"></div>
                    <div class="post-description">${post.content}</div>
                    <div class="post-stats">
                        <span>Лайков: ${post.likes_count || 0}</span>
                        <span>Комментариев: ${post.comments_count || 0}</span>
                    </div>
                    <button class="like-button ${post.liked_by_current_user ? 'liked' : ''}" data-post-id="${post.id}">Лайк</button>
                    <button class="comments-button" data-post-id="${post.id}">Показать комментарии</button>
                    <div class="comments-section" id="comments-${post.id}" style="display: none;">
                        <div class="comments-container"></div>
                        <textarea class="comment-input" placeholder="Напишите комментарий..."></textarea>
                        <button class="submit-comment" data-post-id="${post.id}">Отправить</button>
                    </div>
                `;
                userPostsContainer.appendChild(postElement);

                if (post.route_data && post.route_data.length > 0) {
                    initMap(post.id, post.route_data);
                }
            });
            skip += limit;
        } else {
            loadMoreButton.style.display = 'none';
        }
    } else {
        console.error('Ошибка загрузки постов:', await response.text());
    }
};

    // Загружаем первые посты при открытии страницы
    loadPosts();

    // Обработчик для кнопки "Загрузить еще"
    loadMoreButton.addEventListener('click', loadPosts);

    // Обработчики для лайков, комментариев и отправки комментариев
   document.addEventListener('click', async (event) => {
    if (event.target.classList.contains('comments-button')) {
        const postId = event.target.dataset.postId;
        // Извлекаем user_id из текущего URL (например, /profile/view/{user_id})
        if (postId) {
            // Переход на страницу post_details.html с передачей post_id
            window.location.href = `/post/posts/${postId}/view?post_id=${postId}&source=profile&user_id=${userId}`;
        } else {
            console.error('Post ID is missing');
        }
    } else if (event.target.classList.contains('like-button')) {
        const postId = event.target.dataset.postId;
        const postElement = event.target.closest('.post');
        await likePost(postId, postElement);
    } else if (event.target.classList.contains('submit-comment')) {
        const postId = event.target.dataset.postId;
        await submitComment(postId);
    }
});

    // Проверяем, подписан ли текущий пользователь
    const userId = window.location.pathname.split('/').pop();
    const isFollowingResponse = await fetch(`/friends/is_following/${userId}`, {
        credentials: 'include'
    });

    if (isFollowingResponse.ok) {
        const data = await isFollowingResponse.json();
        if (data.is_following) {
            followButton.textContent = 'Отписаться';
            followButton.classList.add('btn-success');
        } else {
            followButton.textContent = 'Подписаться';
            followButton.classList.remove('btn-success');
        }
    }

    // Обработчик для кнопки "Подписаться"
    followButton.onclick = async () => {
        if (followButton.textContent === 'Подписаться') {
            try {
                const response = await fetch(`/friends/follow/${userId}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    credentials: 'include'
                });

                if (response.ok) {
                    followButton.textContent = 'Отписаться';
                    followButton.classList.add('btn-success');
                } else {
                    console.error('Ошибка при подписке:', await response.text());
                }
            } catch (error) {
                console.error('Ошибка:', error);
            }
        } else {
            const confirmUnfollow = confirm('Вы уверены, что хотите отписаться?');
            if (confirmUnfollow) {
                try {
                    const response = await fetch(`/friends/unfollow/${userId}`, {
                        method: 'DELETE',
                        credentials: 'include'
                    });

                    if (response.ok) {
                        followButton.textContent = 'Подписаться';
                        followButton.classList.remove('btn-success');
                    } else {
                        console.error('Ошибка при отписке:', await response.text());
                    }
                } catch (error) {
                    console.error('Ошибка:', error);
                }
            }
        }
    };
});

// Функция для инициализации карты
function initMap(postId, routeData) {
    console.log("Initializing map for post", postId, "with data:", routeData);

    // Проверка наличия контейнера
    const mapContainer = document.getElementById(`map-${postId}`);
    if (!mapContainer) {
        console.error("Map container not found for post", postId);
        return;
    }

    // Проверка данных маршрута
    if (!routeData || routeData.length === 0) {
        console.error("Route data is empty or invalid for post", postId);
        return;
    }

    // Инициализация карты
    try {
        const map = L.map(mapContainer).setView([routeData[0].latitude, routeData[0].longitude], 13);
        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            attribution: '© OpenStreetMap contributors'
        }).addTo(map);

        const routePoints = routeData.map(point => [point.latitude, point.longitude]);
        L.polyline(routePoints, { color: 'blue' }).addTo(map);
    } catch (error) {
        console.error("Error initializing map:", error);
    }
}

// Кнопка "Начать диалог"
document.getElementById('startChatButton').onclick = () => {
    const userId = window.location.pathname.split('/').pop(); // Получаем user_id из URL
    if (userId) {
        window.location.href = `/chat?user_id=${userId}`; // Перенаправляем на страницу чата
    } else {
        console.error('Не удалось получить user_id из URL');
    }
};

// Функции likePost, loadComments и submitComment остаются такими же, как в вашем исходном коде

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
            if (result.liked) {
                likeButton.classList.add('liked');
            } else {
                likeButton.classList.remove('liked');
            }
        } else if (response.status === 401) {
            window.location.href = '/auth';
        } else {
            console.error('Ошибка при лайке:', await response.json());
        }
    } catch (error) {
        console.error('Ошибка:', error);
    }
}

async function loadComments(postId, postElement) {
    try {
        const response = await fetch(`/post/posts/${postId}/comments`, {
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

        const commentsContainer = postElement.querySelector('.comments-container');
        commentsContainer.innerHTML = '';

        comments.forEach(comment => {
            const commentElement = document.createElement('div');
            commentElement.classList.add('comment');
            commentElement.innerHTML = `
                <span class="comment-author">${comment.user.username}:</span>
                <span class="comment-content">${comment.content}</span>
            `;
            commentsContainer.appendChild(commentElement);
        });

        // Показываем секцию комментариев
        const commentsSection = postElement.querySelector('.comments-section');
        commentsSection.style.display = 'block';
    } catch (error) {
        console.error('Ошибка загрузки комментариев:', error);
    }
}

async function submitComment(postId) {
    const commentInput = document.querySelector(`#comments-${postId} .comment-input`);
    const commentText = commentInput.value.trim();

    if (!commentText) {
        alert("Комментарий не может быть пустым");
        return;
    }

    try {
        const response = await fetch(`/post/posts/${postId}/create_comment`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            credentials: 'include',
            body: JSON.stringify({ content: commentText })
        });

        if (response.ok) {
            commentInput.value = '';  // Очищаем поле ввода
            await loadComments(postId, document.querySelector(`#map-${postId}`).parentElement);
        } else {
            console.error('Ошибка при отправке комментария:', await response.json());
        }
    } catch (error) {
        console.error('Ошибка:', error);
    }
}