// Captura de errores visual en pantalla para depuración
window.onerror = function(message, source, lineno, colno, error) {
    const errorBanner = document.createElement('div');
    errorBanner.style.position = 'fixed';
    errorBanner.style.top = '0';
    errorBanner.style.left = '0';
    errorBanner.style.width = '100%';
    errorBanner.style.backgroundColor = '#ef4444';
    errorBanner.style.color = 'white';
    errorBanner.style.padding = '12px 20px';
    errorBanner.style.zIndex = '999999';
    errorBanner.style.fontFamily = 'monospace';
    errorBanner.style.fontSize = '12px';
    errorBanner.style.boxShadow = '0 4px 12px rgba(0,0,0,0.5)';
    errorBanner.innerHTML = `<strong>Error de JS detectado:</strong> ${message} <br><small>Archivo: ${source} | Línea: ${lineno}:${colno}</small>`;
    document.body.appendChild(errorBanner);
    return false;
};

// Esperar a que el DOM esté listo
document.addEventListener('DOMContentLoaded', () => {
    // Lucide icons
    try {
        if (typeof lucide !== 'undefined') lucide.createIcons();
    } catch (e) {
        console.warn("Lucide no disponible al cargar el DOM:", e);
    }

    // PIN de seguridad
    const AUTH_PIN = '1234';

    // Referencias a elementos de seguridad
    const loginContainer = document.getElementById('login-container');
    const dashboardWrapper = document.getElementById('dashboard-wrapper');
    const loginForm = document.getElementById('login-form');
    const loginPinHidden = document.getElementById('login-pin-hidden');
    const pinSlots = document.querySelectorAll('.pin-slot');
    const keypadButtons = document.querySelectorAll('.key-btn');
    const loginError = document.getElementById('login-error');
    const logoutBtn = document.getElementById('logout-btn');

    // Referencias a elementos del DOM
    const newsCountEl = document.getElementById('news-count');
    const youtubeCountEl = document.getElementById('youtube-count');
    const totalCountEl = document.getElementById('total-count');
    const approvalCountEl = document.getElementById('approval-count');
    const updateTimeEl = document.getElementById('update-time-text');
    const feedGridEl = document.getElementById('feed-grid');
    const searchInputEl = document.getElementById('search-input');
    
    // Botones de filtro
    const sourceFilters = document.querySelectorAll('[data-filter-source]');
    const sentimentFilters = document.querySelectorAll('[data-filter-sentiment]');
    
    // Modal
    const modalOverlay = document.getElementById('detail-modal');
    const modalClose = document.getElementById('modal-close');

    // Estado local de filtros
    let currentSource = 'all';
    let currentSentiment = 'all';
    let searchQuery = '';
    let currentSortOrder = 'desc'; // 'desc' para más reciente, 'asc' para más antiguo
    
    // Datos globales cargados
    let monitorData = { news: [], youtube: [] };
    let filteredItems = [];

    const SESSION_TIMEOUT_MS = 15 * 60 * 1000; // 15 minutos de inactividad

    // Cargar datos iniciales
    setupLoginEvents();
    setupEventListeners();
    checkSessionAndInit();

    function resetInactivityTimeout() {
        if (sessionStorage.getItem('muniwatch_authenticated') === 'true') {
            sessionStorage.setItem('muniwatch_session_time', Date.now().toString());
        }
    }

    function checkInactivity() {
        if (sessionStorage.getItem('muniwatch_authenticated') === 'true') {
            const lastActive = parseInt(sessionStorage.getItem('muniwatch_session_time') || '0', 10);
            if (Date.now() - lastActive > SESSION_TIMEOUT_MS) {
                // Sesión expirada
                sessionStorage.removeItem('muniwatch_authenticated');
                sessionStorage.removeItem('muniwatch_session_time');
                showLogin();
                
                // Mostrar aviso de inactividad
                if (loginError) {
                    loginError.style.display = 'flex';
                    loginError.className = 'login-error-msg';
                    loginError.querySelector('span').textContent = "Sesión cerrada por inactividad. Inicia sesión de nuevo.";
                }
                return true;
            }
        }
        return false;
    }

    function checkSessionAndInit() {
        if (sessionStorage.getItem('muniwatch_authenticated') === 'true') {
            if (checkInactivity()) return;
            resetInactivityTimeout();
            showDashboard();
            // Retraso leve para asegurar que la UI se renderice completamente
            // y evitar problemas de tamaño 0px en los lienzos (canvas) de Chart.js
            setTimeout(() => {
                init();
            }, 100);
            
            // Refrescar el tiempo de inactividad por interacciones del usuario
            const events = ['click', 'mousemove', 'keypress', 'scroll', 'touchstart'];
            events.forEach(name => {
                document.addEventListener(name, resetInactivityTimeout, { passive: true });
            });
        } else {
            showLogin();
        }
    }

    function showDashboard() {
        loginContainer.style.display = 'none';
        dashboardWrapper.style.display = 'block';
    }

    function showLogin() {
        loginContainer.style.display = 'flex';
        dashboardWrapper.style.display = 'none';
        setTimeout(() => {
            if (loginPinHidden) {
                loginPinHidden.focus();
                updatePinUI();
            }
        }, 150);
    }

    function updatePinUI() {
        if (!loginPinHidden) return;
        const val = loginPinHidden.value;
        pinSlots.forEach((slot, idx) => {
            if (idx < val.length) {
                slot.classList.add('filled');
            } else {
                slot.classList.remove('filled');
            }
            
            if (idx === val.length) {
                slot.classList.add('active');
            } else {
                slot.classList.remove('active');
            }
        });
    }

    function submitPin() {
        if (!loginPinHidden) return;
        const pin = loginPinHidden.value;
        if (pin === AUTH_PIN) {
            sessionStorage.setItem('muniwatch_authenticated', 'true');
            sessionStorage.setItem('muniwatch_session_time', Date.now().toString());
            if (loginError) loginError.style.display = 'none';
            
            // Agregar detectores de actividad tras iniciar sesión
            const events = ['click', 'mousemove', 'keypress', 'scroll', 'touchstart'];
            events.forEach(name => {
                document.addEventListener(name, resetInactivityTimeout, { passive: true });
            });

            // Transición animada
            loginContainer.style.opacity = '0';
            loginContainer.style.transform = 'scale(0.95)';
            setTimeout(() => {
                showDashboard();
                init();
            }, 400);
        } else {
            if (loginError) {
                loginError.style.display = 'flex';
                loginError.querySelector('span').textContent = "PIN incorrecto. Intenta de nuevo.";
            }
            // Shaking animation
            const card = loginContainer.querySelector('.login-card');
            if (card) {
                card.classList.add('shake');
                setTimeout(() => {
                    card.classList.remove('shake');
                }, 400);
            }
            // Borrar input
            loginPinHidden.value = '';
            updatePinUI();
        }
    }

    function setupLoginEvents() {
        if (loginPinHidden) {
            // Sincronizar input oculto con la UI visual de los slots
            loginPinHidden.addEventListener('input', () => {
                loginPinHidden.value = loginPinHidden.value.replace(/[^0-9]/g, '');
                updatePinUI();
                if (loginPinHidden.value.length === 4) {
                    submitPin();
                }
            });

            // Enfocar input oculto al hacer clic en el contenedor de slots
            const pinSlotsContainer = document.getElementById('pin-slots-container');
            if (pinSlotsContainer) {
                pinSlotsContainer.addEventListener('click', () => {
                    loginPinHidden.focus();
                });
            }

            // Enfocar input al cargar la pantalla de login
            setTimeout(() => {
                loginPinHidden.focus();
            }, 150);
        }

        // Configurar botones del teclado virtual
        keypadButtons.forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.preventDefault();
                if (!loginPinHidden) return;
                
                const key = btn.getAttribute('data-key');
                if (key === 'clear') {
                    loginPinHidden.value = '';
                } else if (key === 'backspace') {
                    loginPinHidden.value = loginPinHidden.value.slice(0, -1);
                } else if (/^[0-9]$/.test(key)) {
                    if (loginPinHidden.value.length < 4) {
                        loginPinHidden.value += key;
                    }
                }
                
                // Disparar evento de input manualmente
                loginPinHidden.dispatchEvent(new Event('input'));
            });
        });

        if (loginForm) {
            loginForm.addEventListener('submit', (e) => {
                e.preventDefault();
                if (loginPinHidden && loginPinHidden.value.length === 4) {
                    submitPin();
                }
            });
        }
    }

    function init() {
        try {
            // Verificar si la variable global window.monitorData está cargada
            if (window.monitorData) {
                monitorData = window.monitorData;
                hideAlertError();
                processData();
            } else {
                console.warn("No se encontró window.monitorData. Intentando cargar data.json dinámicamente...");
                // Intentar fetch alternativo
                fetch('data.json')
                    .then(response => {
                        if (!response.ok) throw new Error("CORS o error HTTP");
                        return response.json();
                    })
                    .then(data => {
                        monitorData = data;
                        hideAlertError();
                        processData();
                    })
                    .catch(err => {
                        console.error("Error cargando los datos:", err);
                        showAlertError();
                        renderEmptyState(true);
                    });
            }
        } catch (e) {
            console.error("Error crítico en init():", e);
            renderEmptyState(true);
        }
    }

    function showAlertError() {
        const alert = document.getElementById('cors-alert');
        if (alert) alert.style.display = 'flex';
    }

    function hideAlertError() {
        const alert = document.getElementById('cors-alert');
        if (alert) alert.style.display = 'none';
    }

    function processData() {
        try {
            // Combinar datos agregando la propiedad "type" ('news', 'youtube', 'twitter')
            const newsItems = (monitorData.news || []).map(item => ({
                ...item,
                id: item.url,
                type: 'news',
                displaySource: item.source || 'Prensa'
            }));
            
            const youtubeItems = (monitorData.youtube || []).map(item => ({
                ...item,
                id: item.video_id,
                type: 'youtube',
                displaySource: item.channel || 'YouTube'
            }));

            const twitterItems = (monitorData.twitter || []).map(item => ({
                ...item,
                id: item.url,
                type: 'twitter',
                displaySource: `@${item.author || 'Twitter'}`
            }));

            // Combinar y ordenar por fecha (más recientes primero)
            filteredItems = [...newsItems, ...youtubeItems, ...twitterItems].sort((a, b) => {
                return new Date(b.published_date || b.scraped_at) - new Date(a.published_date || a.scraped_at);
            });

            // Actualizar estadísticas en UI
            updateStats(newsItems, youtubeItems, twitterItems, filteredItems);
            
            // Generar gráficos envolviendo en try-catch individual
            try {
                renderCharts(filteredItems);
            } catch (chartErr) {
                console.error("Error dibujando gráficos:", chartErr);
            }

            // Renderizar la lista
            applyFiltersAndRender();
        } catch (processErr) {
            console.error("Error crítico en processData():", processErr);
            renderEmptyState(true);
        }
    }

    function updateStats(news, youtube, twitter, all) {
        newsCountEl.textContent = news.length;
        youtubeCountEl.textContent = youtube.length;
        
        const twitterCountEl = document.getElementById('twitter-count');
        if (twitterCountEl) {
            twitterCountEl.textContent = twitter.length;
        }
        
        totalCountEl.textContent = all.length;
        
        // Calcular porcentaje de sentimiento positivo
        const positiveCount = all.filter(i => i.sentiment === 'positivo').length;
        const negativeCount = all.filter(i => i.sentiment === 'negativo').length;
        const totalSent = positiveCount + negativeCount;
        
        let approvalPercent = 50; // valor neutral base
        if (totalSent > 0) {
            approvalPercent = Math.round((positiveCount / totalSent) * 100);
        }
        approvalCountEl.textContent = `${approvalPercent}%`;
        
        // Actualizar fecha
        if (monitorData.updated_at) {
            const date = new Date(monitorData.updated_at);
            updateTimeEl.textContent = date.toLocaleString('es-PE', { 
                day: '2-digit', month: '2-digit', year: 'numeric', 
                hour: '2-digit', minute: '2-digit', second: '2-digit'
            });
        }
    }

    function setupEventListeners() {
        // Evento Logout
        if (logoutBtn) {
            // Eliminar listeners previos para evitar duplicados
            const newLogoutBtn = logoutBtn.cloneNode(true);
            logoutBtn.parentNode.replaceChild(newLogoutBtn, logoutBtn);
            newLogoutBtn.addEventListener('click', () => {
                sessionStorage.removeItem('muniwatch_authenticated');
                showLogin();
                // Limpiar campos de login
                if (loginPinHidden) {
                    loginPinHidden.value = '';
                    updatePinUI();
                }
                if (loginError) loginError.style.display = 'none';
                loginContainer.style.opacity = '1';
                loginContainer.style.transform = 'scale(1)';
            });
        }

        // Filtro de origen
        sourceFilters.forEach(btn => {
            btn.addEventListener('click', (e) => {
                sourceFilters.forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                currentSource = btn.getAttribute('data-filter-source');
                applyFiltersAndRender();
            });
        });

        // Filtro de sentimiento
        sentimentFilters.forEach(btn => {
            btn.addEventListener('click', (e) => {
                sentimentFilters.forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                currentSentiment = btn.getAttribute('data-filter-sentiment');
                applyFiltersAndRender();
            });
        });

        // Barra de búsqueda con debounce/evento directo
        searchInputEl.addEventListener('input', (e) => {
            searchQuery = e.target.value.toLowerCase().trim();
            applyFiltersAndRender();
        });

        // Evento Ordenación
        const sortOrderBtn = document.getElementById('sort-order-btn');
        const sortOrderText = document.getElementById('sort-order-text');
        const sortOrderIcon = document.getElementById('sort-order-icon');
        if (sortOrderBtn) {
            sortOrderBtn.addEventListener('click', () => {
                if (currentSortOrder === 'desc') {
                    currentSortOrder = 'asc';
                    sortOrderText.textContent = "Antiguos Primero";
                    sortOrderIcon.setAttribute('data-lucide', 'arrow-up-narrow-wide');
                } else {
                    currentSortOrder = 'desc';
                    sortOrderText.textContent = "Recientes Primero";
                    sortOrderIcon.setAttribute('data-lucide', 'arrow-down-narrow-wide');
                }
                lucide.createIcons();
                applyFiltersAndRender();
            });
        }

        // Eventos del Modal
        modalClose.addEventListener('click', closeModal);
        modalOverlay.addEventListener('click', (e) => {
            if (e.target === modalOverlay) closeModal();
        });
        
        // Cerrar modal con la tecla Esc
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') closeModal();
        });

        // Evento cambio de calificación manual
        const sentimentSelect = document.getElementById('modal-sentiment-select');
        if (sentimentSelect) {
            sentimentSelect.addEventListener('change', () => {
                const id = sentimentSelect.getAttribute('data-id');
                const type = sentimentSelect.getAttribute('data-type');
                const newSentiment = sentimentSelect.value;
                if (id && type) {
                    updateSentiment(id, type, newSentiment);
                }
            });
        }
    }

    function applyFiltersAndRender() {
        // Filtrar de la lista maestra "filteredItems" (que contiene todos los items ordenados)
        const newsItems = (monitorData.news || []).map(item => ({ ...item, id: item.url, type: 'news', displaySource: item.source || 'Prensa' }));
        const youtubeItems = (monitorData.youtube || []).map(item => ({ ...item, id: item.video_id, type: 'youtube', displaySource: item.channel || 'YouTube' }));
        const twitterItems = (monitorData.twitter || []).map(item => ({ ...item, id: item.url, type: 'twitter', displaySource: `@${item.author || 'Twitter'}` }));
        
        const allCombined = [...newsItems, ...youtubeItems, ...twitterItems].sort((a, b) => {
            const dateA = new Date(a.published_date || a.scraped_at);
            const dateB = new Date(b.published_date || b.scraped_at);
            return currentSortOrder === 'desc' ? dateB - dateA : dateA - dateB;
        });

        const renderedList = allCombined.filter(item => {
            // Filtro origen
            if (currentSource !== 'all' && item.type !== currentSource) return false;
            
            // Filtro sentimiento
            if (currentSentiment !== 'all' && item.sentiment !== currentSentiment) return false;
            
            // Filtro búsqueda texto
            if (searchQuery) {
                const titleMatch = item.title ? item.title.toLowerCase().includes(searchQuery) : false;
                const sourceMatch = item.displaySource ? item.displaySource.toLowerCase().includes(searchQuery) : false;
                const summaryMatch = item.summary ? item.summary.toLowerCase().includes(searchQuery) : false;
                const transcriptMatch = item.transcript_snippet ? item.transcript_snippet.toLowerCase().includes(searchQuery) : false;
                
                return titleMatch || sourceMatch || summaryMatch || transcriptMatch;
            }
            
            return true;
        });

        renderFeed(renderedList);
    }

    function renderFeed(items) {
        feedGridEl.innerHTML = '';
        
        if (items.length === 0) {
            renderEmptyState(false);
            return;
        }

        items.forEach(item => {
            const card = document.createElement('div');
            card.className = 'feed-card';
            
            const isYoutube = item.type === 'youtube';
            const isTwitter = item.type === 'twitter';
            const isFacebook = item.type === 'news' && (item.url && item.url.includes('facebook.com'));
            
            let iconName = 'newspaper';
            let iconColor = 'color: var(--primary)';
            if (isYoutube) {
                iconName = 'youtube';
                iconColor = 'color: #FF0000';
            } else if (isTwitter) {
                iconName = 'twitter';
                iconColor = 'color: #1D9BF0';
            } else if (isFacebook) {
                iconName = 'facebook';
                iconColor = 'color: #1877F2';
            }
            
            // Formatear fecha y hora de publicación
            let formattedDate = 'Reciente';
            if (item.published_date) {
                try {
                    const d = new Date(item.published_date);
                    if (!isNaN(d.getTime())) {
                        const dateStr = d.toLocaleDateString('es-PE', { day: '2-digit', month: 'short' });
                        const timeStr = d.toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit', hour12: false });
                        formattedDate = `${dateStr}, ${timeStr}`;
                    } else {
                        formattedDate = item.published_date;
                    }
                } catch(e) {
                    formattedDate = item.published_date;
                }
            }

            const snippetText = isYoutube 
                ? (item.transcript_snippet || item.description) 
                : (isTwitter ? (item.title || item.description) : item.summary);
                
            const hasImage = item.image_url && item.image_url.trim() !== "";
            const imageHtml = hasImage 
                ? `<img src="${escapeHtml(item.image_url)}" alt="Vista previa" loading="lazy">` 
                : `<div class="feed-card-placeholder"><i data-lucide="${iconName}"></i></div>`;

            let networkBadgeHtml = '';
            if (isYoutube) {
                networkBadgeHtml = `
                    <div class="network-floating-badge badge-youtube">
                        <svg viewBox="0 0 24 24" fill="currentColor" style="width: 18px; height: 18px; display: block;">
                            <path d="M23.498 6.163a3.003 3.003 0 0 0-2.11-2.11C19.517 3.545 12 3.545 12 3.545s-7.517 0-9.388.508a3.003 3.003 0 0 0-2.11 2.11C0 8.033 0 12 0 12s0 3.967.502 5.837a3.003 3.003 0 0 0 2.11 2.11c1.871.508 9.388.508 9.388.508s7.517 0 9.388-.508a3.003 3.003 0 0 0 2.11-2.11C24 15.967 24 12 24 12s0-3.967-.502-5.837zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/>
                        </svg>
                    </div>`;
            } else if (isTwitter) {
                networkBadgeHtml = `
                    <div class="network-floating-badge badge-twitter">
                        <svg viewBox="0 0 24 24" fill="currentColor" style="width: 14px; height: 14px; display: block;">
                            <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/>
                        </svg>
                    </div>`;
            } else if (isFacebook) {
                networkBadgeHtml = `
                    <div class="network-floating-badge badge-facebook">
                        <svg viewBox="0 0 24 24" fill="currentColor" style="width: 16px; height: 16px; display: block;">
                            <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
                        </svg>
                    </div>`;
            } else {
                networkBadgeHtml = `
                    <div class="network-floating-badge badge-news">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="width: 16px; height: 16px; display: block;">
                            <circle cx="12" cy="12" r="10"></circle>
                            <line x1="2" y1="12" x2="22" y2="12"></line>
                            <path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"></path>
                        </svg>
                    </div>`;
            }

            card.innerHTML = `
                <div class="feed-card-image-container">
                    <div class="feed-card-header">
                        <span class="source-badge">
                            <i data-lucide="${iconName}" style="${iconColor}; width: 16px; height: 16px;"></i>
                            ${escapeHtml(item.displaySource)}
                        </span>
                        <span class="sentiment-badge ${item.sentiment}">
                            ${item.sentiment}
                        </span>
                    </div>
                    ${imageHtml}
                    ${networkBadgeHtml}
                </div>
                <div class="feed-card-body">
                    <h3 class="feed-card-title">${escapeHtml(item.title)}</h3>
                    <p class="feed-card-snippet">${escapeHtml(snippetText)}</p>
                </div>
                <div class="feed-card-footer">
                    <span class="item-date">${escapeHtml(formattedDate)}</span>
                    <button class="action-btn" data-id="${item.id}" data-type="${item.type}">
                        Ver Análisis
                        <i data-lucide="chevron-right" style="width: 16px; height: 16px;"></i>
                    </button>
                </div>
            `;
            
            feedGridEl.appendChild(card);
        });

        try {
            if (typeof lucide !== 'undefined') lucide.createIcons();
        } catch (e) {
            console.warn("Lucide no disponible al renderizar el feed:", e);
        }

        // Configurar botones "Ver Análisis"
        document.querySelectorAll('.action-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const id = btn.getAttribute('data-id');
                const type = btn.getAttribute('data-type');
                openModal(id, type);
            });
        });
    }

    function renderEmptyState(isInitialError) {
        feedGridEl.innerHTML = `
            <div class="empty-state">
                <i data-lucide="${isInitialError ? 'alert-triangle' : 'search'}"></i>
                <h3>${isInitialError ? 'Falta recopilar datos' : 'No hay resultados'}</h3>
                <p>
                    ${isInitialError 
                        ? 'Ejecuta el script principal de Python (<code>python main.py</code>) en la terminal para conectarte a los medios de comunicación e importar las primeras noticias.' 
                        : 'Prueba a cambiar tus filtros o tu término de búsqueda actual.'}
                </p>
            </div>
        `;
        lucide.createIcons();
    }

    // Modal Operations
    function openModal(id, type) {
        // Encontrar el item
        let item = null;
        if (type === 'news') {
            item = monitorData.news.find(i => i.url === id);
        } else if (type === 'youtube') {
            item = monitorData.youtube.find(i => i.video_id === id);
        } else if (type === 'twitter') {
            item = monitorData.twitter.find(i => i.url === id);
        }

        if (!item) return;

        const isYoutube = type === 'youtube';
        const isTwitter = type === 'twitter';
        
        // Rellenar información básica
        document.getElementById('modal-title').textContent = item.title;
        document.getElementById('modal-source').textContent = isYoutube ? (item.channel || 'YouTube') : (isTwitter ? `@${item.author || 'Twitter'}` : (item.source || 'Prensa'));
        document.getElementById('modal-date').textContent = new Date(item.published_date || item.scraped_at).toLocaleString('es-PE');
        
        // Sentimiento
        const sentBadge = document.getElementById('modal-sentiment');
        sentBadge.textContent = `${item.sentiment} (Score: ${item.sentiment_score})`;
        sentBadge.className = `sentiment-badge ${item.sentiment}`;

        // Configurar selector de sentimiento
        const sentimentSelect = document.getElementById('modal-sentiment-select');
        if (sentimentSelect) {
            sentimentSelect.value = item.sentiment;
            sentimentSelect.setAttribute('data-id', id);
            sentimentSelect.setAttribute('data-type', type);
        }

        // Contenido / Texto principal
        const detailsContainer = document.getElementById('modal-details');
        detailsContainer.innerHTML = '';

        if (isYoutube) {
            // Insertar iframe del video
            const videoWrapper = document.createElement('div');
            videoWrapper.className = 'modal-video-container';
            videoWrapper.innerHTML = `
                <iframe src="https://www.youtube.com/embed/${item.video_id}" 
                        frameborder="0" 
                        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" 
                        allowfullscreen>
                </iframe>
            `;
            detailsContainer.appendChild(videoWrapper);

            // Transcripción
            const transTitle = document.createElement('h4');
            transTitle.textContent = "Fragmento Relevante Detectado (Subtítulos)";
            detailsContainer.appendChild(transTitle);

            const transPara = document.createElement('p');
            transPara.innerHTML = highlightKeywords(item.transcript_snippet || item.description);
            detailsContainer.appendChild(transPara);
        } else if (isTwitter) {
            // Tweet
            const tweetTitle = document.createElement('h4');
            tweetTitle.textContent = "Contenido del Tweet";
            detailsContainer.appendChild(tweetTitle);

            const tweetPara = document.createElement('p');
            tweetPara.innerHTML = highlightKeywords(item.title);
            detailsContainer.appendChild(tweetPara);
        } else {
            // Artículo de noticias
            const artTitle = document.createElement('h4');
            artTitle.textContent = "Resumen del Artículo";
            detailsContainer.appendChild(artTitle);

            const artPara = document.createElement('p');
            artPara.innerHTML = highlightKeywords(item.summary);
            detailsContainer.appendChild(artPara);
        }

        // Configurar botón "Ver fuente original"
        const visitBtn = document.getElementById('modal-visit-btn');
        visitBtn.href = isYoutube ? `https://www.youtube.com/watch?v=${item.video_id}` : item.url;
        visitBtn.innerHTML = `
            Ver Fuente Original
            <i data-lucide="external-link" style="width: 16px; height: 16px;"></i>
        `;
        lucide.createIcons();

        // Mostrar Modal
        modalOverlay.classList.add('open');
        document.body.style.overflow = 'hidden'; // Evitar scroll de fondo
    }

    function closeModal() {
        modalOverlay.classList.remove('open');
        document.body.style.overflow = ''; // Habilitar scroll
        
        // Detener video de YouTube si está sonando al limpiar el modal
        const detailsContainer = document.getElementById('modal-details');
        detailsContainer.innerHTML = '';
    }

    function updateSentiment(id, type, newSentiment) {
        let item = null;
        if (type === 'news') {
            item = monitorData.news.find(i => i.url === id);
        } else if (type === 'youtube') {
            item = monitorData.youtube.find(i => i.video_id === id);
        } else if (type === 'twitter') {
            item = monitorData.twitter.find(i => i.url === id);
        }

        if (!item) return;

        const sentBadge = document.getElementById('modal-sentiment');
        if (sentBadge) {
            sentBadge.textContent = 'Guardando...';
            sentBadge.className = 'sentiment-badge neutral';
        }

        const host = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1' ? '' : 'http://localhost:5000';
        fetch(host + '/api/update-sentiment', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                id: id,
                type: type,
                sentiment: newSentiment
            })
        })
        .then(response => {
            if (!response.ok) {
                throw new Error('Error al conectar con el servidor local');
            }
            return response.json();
        })
        .then(data => {
            // Éxito: Actualizar estado local y re-renderizar
            item.sentiment = newSentiment;
            item.sentiment_score = newSentiment === 'positivo' ? 1.0 : (newSentiment === 'negativo' ? -1.0 : 0.0);
            
            if (sentBadge) {
                sentBadge.textContent = `${newSentiment} (Score: ${item.sentiment_score})`;
                sentBadge.className = `sentiment-badge ${newSentiment}`;
            }

            processData();
        })
        .catch(err => {
            console.error("Error actualizando sentimiento:", err);
            if (sentBadge) {
                sentBadge.textContent = `${item.sentiment} (Error)`;
                sentBadge.className = `sentiment-badge ${item.sentiment}`;
            }
            const sentimentSelect = document.getElementById('modal-sentiment-select');
            if (sentimentSelect) {
                sentimentSelect.value = item.sentiment;
            }
            alert('No se pudo guardar el cambio. Asegúrate de tener el servidor del dashboard ejecutándose localmente (run-dashboard.ps1).');
        });
    }

    // Helper functions
    function escapeHtml(text) {
        if (!text) return "";
        const map = {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#039;'
        };
        return text.toString().replace(/[&<>"']/g, function(m) { return map[m]; });
    }

    function highlightKeywords(text) {
        if (!text) return "No hay contenido disponible.";
        const escaped = escapeHtml(text);
        
        const keywords = ["jesús maría", "jesus maria", "jesús gálvez", "jesus galvez", "municipalidad"];
        let highlighted = escaped;
        
        keywords.forEach(kw => {
            const regex = new RegExp(`(${kw})`, 'gi');
            highlighted = highlighted.replace(regex, '<mark style="background-color: rgba(99, 102, 241, 0.3); color: white; padding: 2px 4px; border-radius: 4px; font-weight: 600;">$1</mark>');
        });
        
        return highlighted;
    }

    // Renderizar Gráficos con Chart.js
    let sentimentChart = null;
    let timelineChart = null;

    function renderCharts(items) {
        if (typeof Chart === 'undefined') {
            console.warn("Chart.js no está cargado. Saltando renderizado de gráficos.");
            return;
        }
        try {
            // 1. Gráfico de Sentimiento (Doughnut)
        const pos = items.filter(i => i.sentiment === 'positivo').length;
        const neu = items.filter(i => i.sentiment === 'neutral').length;
        const neg = items.filter(i => i.sentiment === 'negativo').length;

        const ctxSent = document.getElementById('sentiment-chart').getContext('2d');
        
        if (sentimentChart) sentimentChart.destroy();
        
        sentimentChart = new Chart(ctxSent, {
            type: 'doughnut',
            data: {
                labels: ['Positivo', 'Neutro', 'Negativo'],
                datasets: [{
                    data: [pos, neu, neg],
                    backgroundColor: [
                        '#10B981', // Emerald Green
                        '#6B7280', // Gray
                        '#EF4444'  // Coral Red
                    ],
                    borderColor: 'rgba(11, 15, 25, 0.9)',
                    borderWidth: 3,
                    hoverOffset: 4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            color: '#e5e7eb',
                            font: { family: 'Outfit', size: 12 }
                        }
                    }
                },
                cutout: '65%'
            }
        });

        // 2. Gráfico de Tendencia de Menciones (Line Chart por día)
        // Agrupar por fecha
        const dateCounts = {};
        items.forEach(item => {
            let day = 'Reciente';
            if (item.published_date) {
                try {
                    const d = new Date(item.published_date);
                    if (!isNaN(d.getTime())) {
                        day = d.toLocaleDateString('es-PE', { day: '2-digit', month: '2-digit' });
                    }
                } catch(e) {}
            }
            if (day !== 'Reciente') {
                dateCounts[day] = (dateCounts[day] || 0) + 1;
            }
        });

        // Ordenar fechas cronológicamente
        const dates = Object.keys(dateCounts).sort((a,b) => {
            const [da, ma] = a.split('/').map(Number);
            const [db, mb] = b.split('/').map(Number);
            return new Date(2026, ma - 1, da) - new Date(2026, mb - 1, db);
        });
        
        const counts = dates.map(d => dateCounts[d]);

        // Si tenemos muy pocos datos de fechas, agregar valores dummy para que se visualice
        const chartLabels = dates.length > 0 ? dates : ['Hoy'];
        const chartData = counts.length > 0 ? counts : [items.length];

        const ctxTime = document.getElementById('timeline-chart').getContext('2d');
        
        if (timelineChart) timelineChart.destroy();

        // Crear gradiente lineal para la curva
        const primaryGradient = ctxTime.createLinearGradient(0, 0, 0, 300);
        primaryGradient.addColorStop(0, 'rgba(99, 102, 241, 0.4)');
        primaryGradient.addColorStop(1, 'rgba(99, 102, 241, 0.0)');

        timelineChart = new Chart(ctxTime, {
            type: 'line',
            data: {
                labels: chartLabels,
                datasets: [{
                    label: 'Menciones',
                    data: chartData,
                    borderColor: '#6366F1',
                    borderWidth: 3,
                    fill: true,
                    backgroundColor: primaryGradient,
                    tension: 0.35,
                    pointBackgroundColor: '#818cf8',
                    pointBorderColor: '#070a13',
                    pointBorderWidth: 2,
                    pointRadius: 5,
                    pointHoverRadius: 7
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false }
                },
                scales: {
                    y: {
                        grid: { color: 'rgba(255, 255, 255, 0.05)' },
                        ticks: { color: '#9ca3af', font: { family: 'Outfit' }, stepSize: 1 }
                    },
                    x: {
                        grid: { display: false },
                        ticks: { color: '#9ca3af', font: { family: 'Outfit' } }
                    }
                }
            }
        });
        } catch (err) {
            console.error("Error crítico en renderCharts():", err);
        }
    }
});
