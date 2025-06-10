// Обработка кликов по вкладкам
document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => showTab(tab.dataset.tab));
});

// Функция отображения выбранной вкладки
function showTab(tabName) {
    document.querySelectorAll('.tab').forEach(tab => tab.classList.remove('active'));
    document.querySelectorAll('.form').forEach(form => form.classList.remove('active'));

    const tabElement = document.querySelector(`.tab[data-tab="${tabName}"]`);
    const formElement = document.getElementById(`${tabName}Form`);
    if (tabElement && formElement) {
        tabElement.classList.add('active');
        formElement.classList.add('active');
    }
}

// Функция для валидации данных формы
const validateForm = fields => fields.every(field => field && field.trim() !== '');

// Функция для отправки запросов
const sendRequest = async (url, data) => {
    console.log("Отправка запроса на URL:", url); // Логирование
    try {
        const response = await fetch(url, {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify(data)
        });

        let result;
        try {
            result = await response.json();
        } catch (jsonError) {
            console.error("Ошибка парсинга JSON:", jsonError);
            alert('Ошибка при обработке ответа сервера');
            return null;
        }

        if (response.ok) {
            alert(result.message || 'Операция выполнена успешно!');
            return result;
        } else {
            alert(result.message || 'Ошибка выполнения запроса!');
            console.error("Ошибка выполнения запроса:", result);
            return null;
        }
    } catch (error) {
        console.error("Ошибка:", error);
        alert('Произошла ошибка на сервере');
    }
};

// Функция для обработки формы
const handleFormSubmit = async (formType, url, fields) => {
    if (!validateForm(fields)) {
        alert('Пожалуйста, заполните все поля.');
        return;
    }

    const data = await sendRequest(url, formType === 'login'
        ? {email: fields[0], password: fields[1]}
        : {email: fields[0], full_name: fields[1], password: fields[2], password_check: fields[3]});

    if (data && formType === 'login') {
        window.location.href = '/chat';
    }
};

// Обработка формы входа
document.getElementById('loginButton').addEventListener('click', async (event) => {
    event.preventDefault();

    const emailInput = document.querySelector('#loginForm input[type="email"]');
    const passwordInput = document.querySelector('#loginForm input[type="password"]');
    if (!emailInput || !passwordInput) {
        alert('Форма входа не найдена.');
        return;
    }
    const email = emailInput.value;
    const password = passwordInput.value;

    await handleFormSubmit('login', 'login/', [email, password]);
});

// Обработка формы регистрации
document.getElementById('registerButton').addEventListener('click', async (event) => {
    event.preventDefault();
    console.log("Кнопка регистрации нажата"); // Логирование

    const emailInput = document.querySelector('#registerForm input[type="email"]');
    const fullNameInput = document.querySelector('#registerForm input[type="text"]');
    const passwordInputs = document.querySelectorAll('#registerForm input[type="password"]');
    if (!emailInput || !fullNameInput || passwordInputs.length < 2) {
        alert('Форма регистрации не найдена.');
        return;
    }
    const email = emailInput.value;
    const full_name = fullNameInput.value;
    const password = passwordInputs[0].value;
    const password_check = passwordInputs[1].value;

    console.log("Данные формы:", { email, full_name, password, password_check }); // Логирование

    if (password !== password_check) {
        alert('Пароли не совпадают.');
        return;
    }

    await handleFormSubmit('register', 'register/', [email, full_name, password, password_check]);
});