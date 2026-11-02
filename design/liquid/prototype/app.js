"use strict";

const paths = {
  back: "m15 5-7 7 7 7", chevron: "m9 5 7 7-7 7",
  search: "M21 21l-5-5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0",
  compose: "m14 5 5 5M12 7H5v14h14v-7M10 14l1-4L19 2l4 4-8 8-5 1",
  chat: "M21 11a9 9 0 0 1-9 9H8l-6 3 2-6a9 9 0 1 1 17-6Z",
  phone: "m7 2 4 6-3 3c1 3 3 5 6 6l3-3 6 4-2 4C11 25-1 13 2 4Z",
  people: "M16 22v-4c0-6-14-6-14 0v4M14 7a5 5 0 1 1-10 0 5 5 0 0 1 10 0M18 3c5 1 5 7 0 8m0 3c5 1 5 5 5 8",
  settings: "M9 2h6l1 4 4 1 3 5-3 5-4 1-1 4H9l-1-4-4-1-3-5 3-5 4-1ZM16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0",
  archive: "M3 8h18v14H3ZM1 2h22v6H1Zm8 11h6",
  plus: "M12 4v16M4 12h16", up: "M12 20V4m-7 7 7-7 7 7",
  mic: "M8 5a4 4 0 0 1 8 0v7a4 4 0 0 1-8 0ZM4 10v2a8 8 0 0 0 16 0v-2M12 20v3m-4 0h8",
  lock: "M6 10V7a6 6 0 0 1 12 0v3M4 10h16v13H4Zm8 5v4",
  bell: "M4 18h16l-2-3V8A6 6 0 0 0 6 8v7Zm5 3h6",
  check: "m3 12 5 5 10-11m-6 11 10-11", close: "m6 6 12 12M6 18 18 6",
  heart: "M12 21 3 12C-3 5 6-2 12 6c6-8 15-1 9 6Z",
  photo: "M2 3h20v18H2Zm0 13 6-6 6 7 4-4 4 5M18 8h.01",
  network: "M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8 16a6 6 0 0 1 8 0m-4 4h.01",
  appearance: "M12 2a10 10 0 1 0 0 20V2Zm0 0a10 10 0 0 1 0 20",
  storage: "M3 3h18v18H3Zm0 6h18M7 14h10m-10 4h6",
};

const $ = (id) => document.getElementById(id);
const escapeHTML = (text) => String(text).replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const icon = (name, extra = "") => `<svg class="icon ${extra}" viewBox="0 0 24 24" aria-hidden="true"><path d="${paths[name] || paths.chat}"/></svg>`;
const iconButton = (name, label, action) => `<button class="icon-button" aria-label="${label}" data-action="${action}">${icon(name)}</button>`;
const names = Object.fromEntries(window.liquidCatalog.map((scene) => [scene.id, scene.title]));
const primary = new Set(["02_chats", "03_chat", "24_settings", "10_appearance", "12_vault", "27_vault_locked", "15_archive"]);
const initialMessages = [
  { id: 1, text: "Привет! Как насчёт встретиться вечером?", outgoing: false },
  { id: 2, text: "Я заканчиваю в шесть. Буду рядом с парком.", outgoing: false },
  { id: 3, text: "Отлично, давай в 18:30 у входа.", outgoing: true },
  { id: 4, text: "Договорились. Возьму кофе по дороге.", outgoing: false },
  { id: 5, text: "Спасибо! До встречи", outgoing: true, time: "14:42" },
];
const peers = [
  ["АС", "Анна Смирнова", "Спасибо! До встречи", "14:42", 2, ""],
  ["ДК", "Дизайн-команда", "Мария: Добавила комментарии к макету", "13:18", 4, "teal"],
  ["ВК", "Виктор Кузнецов", "Голосовое сообщение · 0:18", "12:04", 0, "gold"],
  ["ИН", "Ирина Новикова", "Фото", "Вчера", 0, "blue"],
  ["ДС", "Дизайн-сообщество", "Новая тема: доступность интерфейса", "Вчера", 1, "teal"],
  ["ИЗ", "Избранное", "Ссылка на исследование", "Пн", 0, "blue"],
  ["НО", "Нина Орлова", "Спасибо за материалы", "Пн", 0, "teal"],
  ["МП", "Максим Попов", "Созвонимся на следующей неделе", "Вс", 0, "gold"],
];

const state = {
  screen: "02_chats", theme: "light", history: [], draft: "", query: "",
  messages: structuredClone(initialMessages), nextId: 6, reply: null, edit: null,
  notifications: true, unlocked: false, error: "", toggles: {},
  selecting: false, selectedPeers: [], archivedNames: ['Нина Орлова', 'Максим Попов'],
  activePeer: 'Анна Смирнова', conversations: {}, drafts: {},
};

function announce(text) { $("announcement").textContent = text; }

function go(next, remember = true) {
  if (!names[next]) return;
  if (remember && next !== state.screen) state.history.push(state.screen);
  state.screen = next === "12_vault" && !state.unlocked ? "27_vault_locked" : next;
  state.error = "";
  render();
}

function back() {
  go(state.history.pop() || "02_chats", false);
}

function tabs(active) {
  return `<nav class="tabs" aria-label="Основные разделы">${[
    ["02_chats", "chat", "Чаты"], ["23_call_history", "phone", "Звонки"],
    ["36_new_message", "people", "Контакты"], ["24_settings", "settings", "Настройки"],
  ].map(([id, name, label]) => `<button class="tab" data-go="${id}" ${active === id ? 'aria-current="page"' : ""}>${icon(name)}<span>${label}</span></button>`).join("")}</nav>`;
}

function chatRows() {
  const query = state.query.toLocaleLowerCase("ru");
  const annaMessages = state.activePeer === 'Анна Смирнова' ? state.messages : state.conversations['Анна Смирнова'] || initialMessages;
  const inArchive = state.screen === '15_archive';
  const found = peers.filter((peer) => state.archivedNames.includes(peer[1]) === inArchive && (peer[1].toLocaleLowerCase("ru").includes(query) || peer[2].toLocaleLowerCase("ru").includes(query)));
  return found.length ? found.map(([letters, name, preview, time, unread, color]) => `<button class="chat-row" data-peer="${name}" ${state.selecting ? `data-select="${name}" role="checkbox" aria-checked="${state.selectedPeers.includes(name)}"` : `data-go="${name === 'Дизайн-сообщество' ? '05_topics' : name === 'Дизайн-команда' ? '17_group_chat' : '03_chat'}"`} aria-label="${name}${unread ? ', непрочитанных: ' + unread : ''}">
    ${state.selecting ? `<span class="selection-indicator" aria-hidden="true">${state.selectedPeers.includes(name) ? icon('check') : ''}</span>` : ''}
    <span class="avatar ${color}" aria-hidden="true">${letters}</span><span class="chat-copy"><span class="row-heading"><strong>${name}</strong><time>${time}</time></span><span class="row-preview"><p>${escapeHTML(name === 'Анна Смирнова' && !state.query ? annaMessages.at(-1)?.text || preview : preview)}</p>${unread ? `<span class="badge" aria-hidden="true">${unread}</span>` : ""}</span></span></button>`).join("") : '<p class="empty" role="status">Ничего не найдено.<br>Попробуйте другое имя или слово.</p>';
}

function chats() {
  const inArchive = state.screen === '15_archive';
  return `<div class="scroll"><div class="toolbar">${inArchive ? iconButton('back','Назад к чатам','back') : `<button class="text-button" data-action="selection">${state.selecting ? 'Готово' : 'Изменить'}</button>`}${iconButton("compose", "Новое сообщение", "compose")}</div><h3 class="large-title">${inArchive ? 'Архив' : 'BananaGram'}</h3>
    <label class="search-box">${icon("search")}<input id="chat-search" type="search" aria-label="Поиск по чатам" placeholder="Поиск" value="${escapeHTML(state.query)}"></label>
    ${inArchive ? '' : `<button class="archive-row" data-go="15_archive"><span class="archive-icon">${icon("archive")}</span><span class="archive-copy"><strong>Архив</strong><small>Чатов: ${state.archivedNames.length}</small></span>${icon('chevron','chevron')}</button>`}<div id="chat-rows">${chatRows()}</div></div>${state.selecting && !inArchive ? `<div class="selection-bar"><button class="primary" data-action="archive-selection" ${state.selectedPeers.length ? '' : 'disabled'}>В архив · ${state.selectedPeers.length}</button></div>` : tabs("02_chats")}`;
}

function conversation() {
  const avatar = peers.find((peer) => peer[1] === state.activePeer)?.[0] || '';
  const messages = state.messages.map((message, index) => {
    const next = state.messages[index + 1];
    const ends = !next || next.outgoing !== message.outgoing;
    return `<article class="message ${message.outgoing ? 'out' : ''} ${ends ? 'group-end' : ''}" data-message="${message.id}">
      <button class="bubble" data-menu="${message.id}" aria-label="${escapeHTML(message.text)}. Действия с сообщением">${message.reply ? `<span class="quote">${escapeHTML(message.reply)}</span>` : ""}${escapeHTML(message.text)}${ends ? '<svg class="bubble-tail" viewBox="0 0 14 20" aria-hidden="true"><path d="M14 0H7v8c0 5-3 10-7 12 6 0 11-2 14-6Z"/></svg>' : ''}</button>
      ${message.reaction ? `<button class="reaction" data-react="${message.id}" aria-label="Убрать реакцию Нравится">${icon("heart")} 1</button>` : ""}
      ${message.time ? `<span class="message-meta"><time>${message.time}</time>${message.outgoing ? icon("check") : ''}<span class="sr-only">${message.outgoing ? 'Прочитано' : ''}</span></span>` : ""}</article>`;
  }).join("");
  const banner = state.edit ? `Редактирование: ${state.edit.text}` : state.reply ? `Ответ: ${state.reply.text}` : "";
  return `<header class="toolbar">${iconButton("back", "Назад к чатам", "back")}<button class="contact-button" data-go="06_profile"><span class="avatar" aria-hidden="true">${avatar}</span><span><strong>${escapeHTML(state.activePeer)}</strong><small>была недавно</small></span></button>${iconButton("phone", "Позвонить контакту", "call")}</header>
    <div class="scroll conversation" id="conversation" aria-label="Сообщения"><span class="day">Сегодня</span>${messages}</div>
    <form class="composer" id="composer">${banner ? `<div class="compose-banner"><span>${escapeHTML(banner)}</span>${iconButton("close", "Отменить ответ или редактирование", "cancel-edit")}</div>` : ""}
    <div class="compose-line">${iconButton("plus", "Добавить вложение", "attachment")}<label class="input-capsule"><textarea id="message-input" aria-label="Сообщение" placeholder="Сообщение" rows="1" maxlength="4096">${escapeHTML(state.draft)}</textarea></label><button id="send" class="icon-button compose-submit ${state.draft.trim() ? 'send' : ''}" type="submit" aria-label="${state.draft.trim() ? 'Отправить сообщение' : 'Записать голосовое'}">${icon(state.draft.trim() ? "up" : "mic")}</button></div></form>`;
}

function settingsRow(title, symbol, destination, detail = "") {
  return `<button class="settings-row" data-go="${destination}">${icon(symbol)}<span class="row-name">${title}</span>${detail ? `<small>${detail}</small>` : ""}${icon("chevron", "chevron")}</button>`;
}

function settings() {
  return `<div class="scroll"><div class="toolbar"><span></span><button class="text-button" data-go="35_edit_profile">Изменить</button></div><h3 class="large-title">Настройки</h3>
    <button class="settings-profile" data-go="28_accounts"><span class="avatar blue" aria-hidden="true">АП</span><span><strong>Алексей Петров</strong><small>Личный аккаунт · демо</small></span></button>
    <div class="settings-group">${settingsRow("BananaGram Extras", "plus", "37_extras_root")}</div>
    <div class="settings-group">${settingsRow("Уведомления и звуки", "bell", "33_notifications")}${settingsRow("Конфиденциальность", "lock", "46_privacy_security")}${settingsRow("Устройства", "people", "47_sessions")}</div>
    <div class="settings-group">${settingsRow("Данные и память", "storage", "32_storage")}${settingsRow("Оформление", "appearance", "10_appearance")}${settingsRow("Прокси", "network", "25_proxies")}</div>
    <p class="section-caption">Демонстрационное состояние</p><div class="settings-group"><button class="settings-row" role="switch" aria-checked="${state.notifications}" data-action="notifications"><span class="row-name">Звук в приложении</span><span class="switch" aria-hidden="true"></span></button></div></div>${tabs("24_settings")}`;
}

function appearance() {
  return `<header class="toolbar">${iconButton("back", "Назад", "back")}<strong>Оформление</strong><span style="width:44px"></span></header><div class="scroll"><p class="section-caption">Просмотр концепта</p><div class="settings-group">${['light', 'dark'].map((theme) => `<button class="settings-row" data-theme="${theme}" aria-pressed="${state.theme === theme}"><span class="row-name">${theme === 'light' ? 'Светлая' : 'Тёмная'}</span>${state.theme === theme ? icon('check') : ''}</button>`).join('')}</div><div class="demo-content"><p>Это переключение темы макета. В приложении доступны Classic White, Classic Black, Cream и Graphite. Их настройки и автоматическое переключение здесь не меняются.</p></div><div class="conversation"><article class="message"><span class="bubble">Так выглядит входящее сообщение.</span></article><article class="message out"><span class="bubble">А так — исходящее.</span></article></div></div>`;
}

function vault() {
  if (state.screen === '12_vault' && state.unlocked) return `<header class="toolbar">${iconButton('back','Назад','back')}<strong>Защищённый архив</strong>${iconButton('lock','Заблокировать архив','lock')}</header><div class="demo-content"><p>Доступ открыт только в демонстрации. Здесь нет личных данных.</p><button class="primary" data-action="lock">Заблокировать</button></div>`;
  return `<header class="toolbar">${iconButton('back','Назад','back')}<strong>Защищённый архив</strong><span style="width:44px"></span></header><form class="lock" id="unlock">${icon('lock')}<h3>Архив заблокирован</h3><p>Демо-код: 1234.<br>Не вводите настоящий пароль.</p><input id="demo-pin" type="password" inputmode="numeric" maxlength="8" autocomplete="off" aria-label="Демонстрационный код"><button class="primary" type="submit">Открыть демо</button>${state.error ? `<span class="error" role="alert">${state.error}</span>` : ''}<p>Нативная защита, Keychain и Face ID этим макетом не проверяются.</p></form>`;
}

function reference() {
  const id = state.screen;
  return `<div class="reference-view"><div class="reference-banner">Исходный концепт · переработка и приёмка впереди</div><img src="../reference/PNG_3X/${state.theme}/${id}.png" alt="${escapeHTML(names[id])}, исходный концепт ${state.theme}" width="393" height="852"><div class="reference-actions" aria-label="Маршруты исходного концепта">${(window.liquidHotspots[id] || []).map((hit, index) => `<button data-reference="${index}">${escapeHTML(hit.label)}${hit.to.startsWith('@') ? ' · демо' : ''}</button>`).join('')}</div></div>`;
}

function openSheet(title, actions) {
  const sheet = $('sheet');
  sheet.innerHTML = `<h3 id="sheet-title">${escapeHTML(title)}</h3>`;
  for (const action of actions.concat([{ label:'Отмена', run:() => {}, cancel:true }])) {
    const button = document.createElement('button');
    button.textContent = action.label;
    button.className = action.destructive ? 'destructive' : action.cancel ? 'cancel' : '';
    button.onclick = () => { sheet.close(); action.run(); };
    sheet.append(button);
  }
  sheet.showModal();
}

function messageMenu(id) {
  const message = state.messages.find((item) => item.id === id);
  if (!message) return;
  const actions = [
    { label:message.reaction ? 'Убрать «Нравится»' : 'Нравится', run:() => { message.reaction = !message.reaction; render(); } },
    { label:'Ответить', run:() => { state.reply = message; state.edit = null; render(); $('message-input').focus(); } },
  ];
  if (message.outgoing) actions.push({ label:'Изменить', run:() => { state.edit = message; state.reply = null; state.draft = message.text; render(); $('message-input').focus(); } });
  actions.push({ label:'Удалить из демонстрации', destructive:true, run:() => openSheet('Удалить сообщение?', [{ label:'Удалить', destructive:true, run:() => { state.messages = state.messages.filter((item) => item.id !== id); render(); } }]) });
  openSheet('Действия с сообщением', actions);
}

function sendMessage(text) {
  if (state.edit) {
    const message = state.messages.find((item) => item.id === state.edit.id);
    if (message) message.text = text;
  } else {
    state.messages.push({ id:state.nextId++, text, outgoing:true, time:'Сейчас', reply:state.reply?.text });
  }
  state.draft = ''; state.reply = null; state.edit = null;
  state.drafts[state.activePeer] = '';
  render();
  $('conversation').scrollTop = $('conversation').scrollHeight;
  $('message-input').focus();
  announce('Сообщение сохранено в памяти прототипа. Отправки в Telegram нет.');
}

function action(name) {
  if (name === 'back') back();
  if (name === 'compose') go('36_new_message');
  if (name === 'call') go('07_call_audio');
  if (name === 'selection') { state.selecting = !state.selecting; state.selectedPeers = []; render(); }
  if (name === 'archive-selection') {
    state.archivedNames.push(...state.selectedPeers.filter((name) => !state.archivedNames.includes(name)));
    state.selecting = false; state.selectedPeers = []; render(); announce('Чаты перемещены в демонстрационный архив');
  }
  if (name === 'notifications') { state.notifications = !state.notifications; render(); }
  if (name === 'cancel-edit') { state.reply = null; state.edit = null; state.draft = ''; render(); }
  if (name === 'attachment') openSheet('Добавить вложение · демо', [
    {label:'Демонстрационное фото',run:() => sendMessage('[Фото · демонстрационный файл]')},
    {label:'Открыть концепт галереи',run:() => go('08_gallery')},
    {label:'Открыть концепт файлов',run:() => go('22_shared_media')},
  ]);
  if (name === 'lock') { state.unlocked = false; go('27_vault_locked', false); }
}

function render() {
  const id = state.screen;
  document.body.classList.toggle('theme-dark', state.theme === 'dark');
  document.querySelector('.device').classList.toggle('is-reference', !primary.has(id));
  $('screen').className = `screen ${['24_settings','10_appearance'].includes(id) ? 'settings' : ''}`;
  $('screen').innerHTML = ['02_chats','15_archive'].includes(id) ? chats() : id === '03_chat' ? conversation() : id === '24_settings' ? settings() : id === '10_appearance' ? appearance() : ['12_vault','27_vault_locked'].includes(id) ? vault() : reference();
  $('scene-title').textContent = names[id];
  $('scene-status').textContent = primary.has(id) ? 'DOM PROTOTYPE · REVIEW PENDING' : 'IMPORTED · REVIEW PENDING';
  $('scene-description').textContent = primary.has(id) ? 'Редактируемая компоновка и локальное состояние. Геометрия и поведение ещё требуют приёмки на iOS.' : 'Просмотр исходного концепта и его маршрутов. Наличие изображения не означает, что сцена переработана.';
  $('light').setAttribute('aria-pressed', state.theme === 'light');
  $('dark').setAttribute('aria-pressed', state.theme === 'dark');
  $('source-links').innerHTML = `<a href="../reference/FIGMA_EDITABLE_SVG/${state.theme}/${id}.svg" target="_blank" rel="noopener">Исходный редактируемый SVG</a><a href="../specs/imported/${id}.md" target="_blank" rel="noopener">Исходная карточка сцены</a>`;
  document.querySelectorAll('.catalogue-link').forEach((button) => {
    if (button.dataset.go === id) button.setAttribute('aria-current','page'); else button.removeAttribute('aria-current');
  });
  history.replaceState(null, '', `#screen=${id}&theme=${state.theme}`);
  bindScreen();
}

function bindScreen() {
  $('screen').querySelectorAll('[data-select]').forEach((button) => { button.onclick = () => {
    const name = button.dataset.select;
    state.selectedPeers = state.selectedPeers.includes(name) ? state.selectedPeers.filter((peer) => peer !== name) : [...state.selectedPeers, name];
    render();
  }; });
  const follow = (button) => {
    if (button.dataset.peer && button.dataset.go === '03_chat') {
      state.conversations[state.activePeer] = state.messages;
      state.drafts[state.activePeer] = state.draft;
      state.activePeer = button.dataset.peer;
      state.messages = state.conversations[state.activePeer] ||= [];
      state.reply = null; state.edit = null; state.draft = state.drafts[state.activePeer] || '';
    }
    go(button.dataset.go);
  };
  $('screen').querySelectorAll('[data-go]').forEach((button) => { button.onclick = () => follow(button); });
  $('screen').querySelectorAll('[data-action]').forEach((button) => { button.type = 'button'; button.onclick = () => action(button.dataset.action); });
  $('screen').querySelectorAll('[data-theme]').forEach((button) => { button.onclick = () => { state.theme = button.dataset.theme; render(); }; });
  $('screen').querySelectorAll('[data-menu]').forEach((button) => { button.onclick = () => messageMenu(Number(button.dataset.menu)); });
  $('screen').querySelectorAll('[data-react]').forEach((button) => { button.onclick = () => { const message = state.messages.find((item) => item.id === Number(button.dataset.react)); message.reaction = false; render(); }; });
  $('screen').querySelectorAll('[data-reference]').forEach((button) => { button.onclick = () => {
    const hit = window.liquidHotspots[state.screen][Number(button.dataset.reference)];
    if (hit.to.startsWith('@')) {
      const key = state.screen + ':' + button.dataset.reference;
      state.toggles[key] = !state.toggles[key];
      button.textContent = hit.label + ' · демо: ' + (state.toggles[key] ? 'включено' : 'выключено');
      announce('Изменено только демонстрационное состояние. Исходное изображение не менялось.');
    } else go(hit.to);
  }; });
  if ($('chat-search')) $('chat-search').oninput = (event) => {
    state.query = event.target.value; $('chat-rows').innerHTML = chatRows();
    $('chat-rows').querySelectorAll('[data-go]').forEach((button) => { button.onclick = () => follow(button); });
  };
  if ($('message-input')) {
    const input = $('message-input');
    const update = () => {
      input.style.height = 'auto'; input.style.height = Math.min(input.scrollHeight,132) + 'px';
      $('send').setAttribute('aria-label',state.draft.trim() ? 'Отправить сообщение' : 'Записать голосовое');
      $('send').classList.toggle('send',Boolean(state.draft.trim()));
      $('send').innerHTML = icon(state.draft.trim() ? 'up' : 'mic');
    };
    input.oninput = () => { state.draft = input.value; update(); };
    update();
    $('composer').onsubmit = (event) => { event.preventDefault(); const text = state.draft.trim(); if (text) sendMessage(text); else go('21_voice_record'); };
  }
  if ($('unlock')) $('unlock').onsubmit = (event) => {
    event.preventDefault();
    const entered = $('demo-pin').value; $('demo-pin').value = '';
    if (entered === '1234') { state.unlocked = true; go('12_vault',false); }
    else { state.error = 'Неверный демонстрационный код'; render(); $('demo-pin').focus(); }
  };
}

function catalogue() {
  const query = $('catalogue-search').value.toLocaleLowerCase('ru');
  $('catalogue').innerHTML = window.liquidCatalog.filter((scene) => (scene.id + scene.title).toLocaleLowerCase('ru').includes(query)).map((scene) => `<button class="catalogue-link" data-go="${scene.id}"><span>${scene.id.slice(0,2)}</span>${escapeHTML(scene.title)}</button>`).join('');
  $('catalogue').querySelectorAll('button').forEach((button) => { button.onclick = () => go(button.dataset.go); });
}

document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    state.unlocked = false;
    if (['12_vault','27_vault_locked'].includes(state.screen)) {
      if ($('sheet').open) $('sheet').close();
      state.screen = '27_vault_locked'; render();
    }
  }
});

document.addEventListener('DOMContentLoaded', () => {
  const hash = new URLSearchParams(location.hash.slice(1));
  if (names[hash.get('screen')]) state.screen = hash.get('screen');
  if (state.screen === '12_vault') state.screen = '27_vault_locked';
  if (hash.get('theme') === 'dark') state.theme = 'dark';
  catalogue(); render();
  document.querySelector('.device').classList.add('show-tails');
  $('catalogue-search').oninput = catalogue;
  $('light').onclick = () => { state.theme = 'light'; render(); };
  $('dark').onclick = () => { state.theme = 'dark'; render(); };
  $('back').onclick = back;
  $('reset').onclick = () => {
    Object.assign(state, {screen:'02_chats', history:[], draft:'', query:'', messages:structuredClone(initialMessages), nextId:6, reply:null, edit:null, notifications:true, unlocked:false, error:'', toggles:{}, selecting:false, selectedPeers:[], archivedNames:['Нина Орлова','Максим Попов'], activePeer:'Анна Смирнова', conversations:{}, drafts:{}});
    render();
    announce('Демонстрация сброшена');
  };
  $('large-text').onchange = (event) => document.querySelector('.device').classList.toggle('large-text',event.target.checked);
  $('opaque').onchange = (event) => document.body.classList.toggle('opaque',event.target.checked);
  $('reduce-motion').onchange = (event) => document.body.classList.toggle('reduce-motion',event.target.checked);
  $('bubble-tails').onchange = (event) => document.querySelector('.device').classList.toggle('show-tails',event.target.checked);
});
