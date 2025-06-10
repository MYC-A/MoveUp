let currentUserId = null; // ID текущего пользователя
let currentPhotoIndex = 0; // Текущий индекс фотографии
let photoUrls = []; // Массив URL фотографий

// Подключение к WebSocket для ленты новостей
const feedSocket = new WebSocket(`ws://${window.location.host}/post/ws/feed`);

feedSocket.onopen = function (event) {
    console.log("WebSocket соединение для ленты новостей установлено");
};

feedSocket.onerror = function (error) {
    console.error("WebSocket ошибка:", error);
};

feedSocket.onclose = function (event) {
    console.log("WebSocket соединение для ленты новостей закрыто");
};

feedSocket.onmessage = function (event) {
    const update = JSON.parse(event.data);

    if (update.type === "like") {
        const postElement = document.querySelector(`.post[data-post-id="${update.post_id}"]`);
        if (postElement) {
            const likesCount = postElement.querySelector('.post-stats span');
            likesCount.textContent = `Лайков: ${update.likes_count}`;

            // Обновляем кнопку лайка только для текущего пользователя
            const likeButton = postElement.querySelector('.like-button');
            if (update.user_id === currentUserId) {
                likeButton.classList.toggle('liked', update.liked);
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
    } else if (update.type === "photo") {
        const postElement = document.querySelector(`.post[data-post-id="${update.post_id}"]`);
        if (postElement) {
            const gridContainer = postElement.querySelector('.photo-grid');
            if (gridContainer) {
                const photoElement = document.createElement('div');
                photoElement.classList.add('photo-grid-item');
                photoElement.innerHTML = `<img src="${update.photo_url}" alt="Фото поста" class="post-photo">`;
                gridContainer.appendChild(photoElement);

                // Добавляем обработчик клика для новой фотографии
                photoElement.addEventListener('click', () => {
                    const postPhotos = Array.from(postElement.querySelectorAll('.photo-grid-item')).map(
                        (item) => item.dataset.photoUrl
                    );
                    currentPhotoIndex = postPhotos.indexOf(update.photo_url);
                    photoUrls = postPhotos;
                    openModal(photoUrls[currentPhotoIndex]);
                });
            }
        }
    }
};

// Открытие фотографии в модальном окне
document.querySelectorAll('.photo-grid-item').forEach((item, index) => {
    item.addEventListener('click', () => {
        const postElement = item.closest('.post');
        photoUrls = Array.from(postElement.querySelectorAll('.photo-grid-item')).map(
            (item) => item.dataset.photoUrl
        );
        currentPhotoIndex = index;
        openModal(photoUrls[currentPhotoIndex]);
    });
});

// Открытие модального окна
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

// Закрытие модального окна при клике вне изображения
window.addEventListener('click', (event) => {
    const modal = document.getElementById('photo-modal');
    if (event.target === modal) {
        modal.style.display = 'none';
    }
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

// Подключение к WebSocket для отдельного поста (если пользователь на странице поста)
const postId = new URLSearchParams(window.location.search).get('post_id');
if (postId) {
    const postSocket = new WebSocket(`ws://${window.location.host}/post/ws/post/${postId}`);

    postSocket.onopen = function (event) {
        console.log("WebSocket соединение для поста установлено");
    };

    postSocket.onerror = function (error) {
        console.error("WebSocket ошибка:", error);
    };

    postSocket.onclose = function (event) {
        console.log("WebSocket соединение для поста закрыто");
    };

    postSocket.onmessage = function (event) {
        const update = JSON.parse(event.data);

        if (update.type === "like") {
            const likesCount = document.querySelector('.post-stats span');
            likesCount.textContent = `Лайков: ${update.likes_count}`;

            const likeButton = document.querySelector('.like-button');
            if (update.user_id === currentUserId) {
                likeButton.classList.toggle('liked', update.liked);
            }
        } else if (update.type === "comment") {
            const commentsContainer = document.querySelector('.comments-container');
            const commentElement = document.createElement('div');
            commentElement.classList.add('comment');
            commentElement.innerHTML = `
                <span class="comment-author">${update.comment.user.username}:</span>
                <span class="comment-content">${update.comment.content}</span>
            `;
            commentsContainer.appendChild(commentElement);

            const commentsCount = document.querySelector('.post-stats span:nth-child(2)');
            const currentCount = parseInt(commentsCount.textContent.replace("Комментариев: ", ""), 10);
            commentsCount.textContent = `Комментариев: ${currentCount + 1}`;
        }
    };
}

document.addEventListener('DOMContentLoaded', async () => {
    // Получаем ID текущего пользователя
    const userResponse = await fetch('/auth/current_user', { credentials: 'include' });
    if (userResponse.ok) {
        const userData = await userResponse.json();
        currentUserId = userData.id;
    }

    // Обработчик для кнопок лайка
    document.querySelectorAll('.like-button').forEach(button => {
        button.addEventListener('click', async () => {
            const postId = button.dataset.postId;
            const postElement = button.closest('.post');
            await likePost(postId, postElement);
        });
    });

    // Обработчик для кнопок комментариев
    document.querySelectorAll('.comments-button').forEach(button => {
        button.addEventListener('click', async () => {
            const postId = button.dataset.postId;
            if (feedSocket) {
                feedSocket.close(); // Закрываем соединение для ленты
            }
            window.location.href = `/post/posts/${postId}/view?post_id=${postId}&source=feed`;
        });
    });

    // Обработчик для кнопки "Мероприятия"
    document.querySelector('button[onclick="window.location.href=\'/events\'"]').addEventListener('click', () => {
        window.location.href = '/events';
    });

    // Обработчик для отправки комментариев
    document.querySelectorAll('.submit-comment').forEach(button => {
        button.addEventListener('click', async () => {
            const postId = button.dataset.postId;
            await submitComment(postId);
        });
    });
});

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