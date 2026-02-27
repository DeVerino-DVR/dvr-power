const HUD = {
    hunger: 100,
    thirst: 100,
    magicHp: 100,
    potion: 100
};

const SPELL_COLOR_MAP = {
    red: '#ff5d5d',
    blue: '#4fa6ff',
    green: '#4dff8a',
    purple: '#c084ff',
    yellow: '#ffe178',
    white: '#f5f5f5',
    black: '#3c3c4f',
    orange: '#ff9d5d',
    light: '#ece3ff',
    dark: '#5b5b7a',
    fire: '#ff7b5c',
    water: '#5cc6ff',
    heal: '#8bffa8',
    control: '#a7a0ff',
    defense: '#5cc6ff',
    attack: '#ff7b5c',
    utility: '#ffd66b',
    summon: '#d89bff'
};

const POSITION_INFO = {
    top: { label: 'Haut', key: '7' },
    left: { label: 'Gauche', key: '6' },
    right: { label: 'Droite', key: '9' },
    center: { label: 'Centre', key: 'H' },
    bottom: { label: 'Bas', key: '8' }
};

const DEFAULT_ACCENT = '#f5d26c';
const DEFAULT_KEYS = {
    top: '7',
    left: '6',
    center: 'H',
    right: '9',
    bottom: '8'
};
const MAX_SPELL_LEVEL = 5;
const DEFAULT_PREVIEW_IMAGE = 'YOUR_PREVIEW_IMAGE_URL_HERE';

let dynamicKeys = { ...DEFAULT_KEYS };
const lockFeedbackTimers = new Map();
let magicDamageOverlayTimeout = null;

const selectorState = {
    visible: false,
    spells: [],
    spellLookup: new Map(),
    slotAssignments: {
        top: null,
        left: null,
        center: null,
        right: null,
        bottom: null
    },
    selectedSpellId: null,
    draggingSpellId: null,
    isDragging: false,
    dragElement: null,
    dragOffset: { x: 0, y: 0 },
    activeFilter: 'all',
    searchQuery: ''
};

const dom = {
    hud: document.getElementById('hud'),
    selector: document.getElementById('spell-selector'),
    grid: document.getElementById('spell-grid'),
    searchInput: document.getElementById('spell-search-input'),
    previewTitle: document.getElementById('preview-title'),
    previewDescription: document.getElementById('preview-description'),
    previewVideo: document.getElementById('preview-video'),
    previewImage: document.getElementById('preview-image'),
    previewPlaceholder: document.querySelector('.hl-preview-placeholder'),
    filterToggle: document.getElementById('filter-toggle'),
    filterDropdown: document.getElementById('filter-dropdown')
};

const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nui-frame';

function postNui(eventName, data) {
    try {
        fetch(`https://${resourceName}/${eventName}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json; charset=UTF-8'
            },
            body: JSON.stringify(data || {})
        }).catch(err => {
            console.error(`[NUI] Failed to post ${eventName}:`, err);
        });
    } catch (err) {}
}

function resolveAccent(colorKey) {
    if (!colorKey) {
        return DEFAULT_ACCENT;
    }

    const normalized = String(colorKey).toLowerCase();
    return SPELL_COLOR_MAP[normalized] || DEFAULT_ACCENT;
}

function hexToRgb(hex) {
    if (!hex) {
        return null;
    }

    let cleaned = hex.replace('#', '').trim();
    if (cleaned.length === 3) {
        cleaned = cleaned.split('').map((c) => c + c).join('');
    }

    if (cleaned.length !== 6) {
        return null;
    }

    const value = parseInt(cleaned, 16);
    if (Number.isNaN(value)) {
        return null;
    }

    return {
        r: (value >> 16) & 255,
        g: (value >> 8) & 255,
        b: value & 255
    };
}

function applySpellAccent(diamond, hex) {
    if (!diamond) return;
    const accent = hex || DEFAULT_ACCENT;
    const rgb = hexToRgb(accent.startsWith('#') ? accent : `#${accent}`);

    diamond.style.setProperty('--spell-accent', accent.startsWith('#') ? accent : `#${accent}`);

    if (rgb) {
        diamond.style.setProperty('--spell-accent-rgb', `${rgb.r}, ${rgb.g}, ${rgb.b}`);
    } else {
        diamond.style.removeProperty('--spell-accent-rgb');
    }
}

function formatSpellName(name) {
    if (!name) {
        return '';
    }

    const trimmed = name.trim();
    if (trimmed.length <= 50) {
        return trimmed;
    }

    const words = trimmed.split(/\s+/);
    if (words.length > 1) {
        const combined = words.slice(0, 3).join(' ');
        if (combined.length <= 50) {
            return combined;
        }
    }

    return `${trimmed.slice(0, 47)}...`;
}

function buildBaseSlotSkeleton(diamond, position) {
    const info = POSITION_INFO[position] || { label: position.toUpperCase(), key: dynamicKeys[position] || '' };
    diamond.dataset.positionLabel = info.label;

    const positionLabel = document.createElement('div');
    positionLabel.className = 'spell-position-label';
    positionLabel.textContent = info.label;
    diamond.appendChild(positionLabel);

    const keyText = dynamicKeys[position] || info.key || '';
    diamond.dataset.keyLabel = keyText;

    const keyElement = document.createElement('div');
    keyElement.className = 'spell-key';
    keyElement.textContent = keyText;
    diamond.appendChild(keyElement);

    return info;
}

function ensureLockOverlay(diamond) {
    if (!diamond) return null;
    let overlay = diamond.querySelector('.lock-feedback');
    if (!overlay) {
        overlay = document.createElement('div');
        overlay.className = 'lock-feedback';

        const icon = document.createElement('div');
        icon.className = 'lock-icon';
        const text = document.createElement('div');
        text.className = 'lock-text';
        overlay.appendChild(icon);
        overlay.appendChild(text);
        diamond.appendChild(overlay);
    } else {
        overlay.classList.remove('visible');
    }
    return overlay;
}

function handleLockedDiamondClick(event) {
    const diamond = event.currentTarget;
    if (!diamond.classList.contains('locked')) {
        return;
    }

    const overlay = ensureLockOverlay(diamond);
    if (!overlay) {
        return;
    }

    overlay.classList.add('visible');
    diamond.classList.add('lock-feedback-active');

    if (lockFeedbackTimers.has(diamond)) {
        clearTimeout(lockFeedbackTimers.get(diamond));
    }

    const timer = setTimeout(() => {
        overlay.classList.remove('visible');
        diamond.classList.remove('lock-feedback-active');
        lockFeedbackTimers.delete(diamond);
    }, 1600);

    lockFeedbackTimers.set(diamond, timer);
}

function initializeLockHandlers() {
    const diamonds = document.querySelectorAll('.spell-diamond');
    diamonds.forEach((diamond) => {
        if (!diamond.dataset.lockHandlerAttached) {
            diamond.addEventListener('click', handleLockedDiamondClick);
            diamond.dataset.lockHandlerAttached = '1';
        }
    });
}

function updateBar(id, value) {
    value = Math.max(0, Math.min(100, value));
    const bar = document.getElementById(id);
    if (bar) {
        bar.style.width = `${value}%`;
        const parentElement = bar.parentElement;
        if (parentElement) {
            parentElement.classList.remove('low', 'critical');
            if (value <= 20) {
                parentElement.classList.add('critical');
            } else if (value <= 40) {
                parentElement.classList.add('low');
            }
        }
    }
}

function updateHealthText(current, max) {
    const el = document.getElementById('bar-health-text');
    if (!el) return;
    const currentNum = Number(current);
    const maxNum = Number(max);
    if (!Number.isFinite(currentNum) || !Number.isFinite(maxNum) || maxNum <= 0) {
        el.textContent = '';
        return;
    }
    el.textContent = `${Math.floor(currentNum)}/${Math.floor(maxNum)}HP`;
}

function setSpell(position, spell) {
    const diamond = document.getElementById('spell-' + position);
    if (!diamond) return;

    const wasLocked = diamond.classList.contains('locked');
    diamond.className = 'spell-diamond spell-' + (position === 'center' ? 'center' : 'small');
    if (wasLocked) {
        diamond.classList.add('locked');
    }

    const existingCooldown = diamond.querySelector('.spell-cooldown');

    diamond.innerHTML = '';
    diamond.dataset.position = position;
    diamond.dataset.spellId = spell && spell.id ? spell.id : '';
    diamond.classList.remove('spell-empty', 'spell-filled', 'has-spell', 'has-accent');

    buildBaseSlotSkeleton(diamond, position);

    if (!spell) {
        diamond.classList.add('spell-empty');
        diamond.style.setProperty('--spell-icon', 'none');
        diamond.style.removeProperty('--spell-accent');
        diamond.style.removeProperty('--spell-accent-rgb');
        diamond.style.removeProperty('--spell-level-ratio');
        diamond.style.removeProperty('--spell-level-angle');
        diamond.removeAttribute('title');
        diamond.dataset.spellId = '';

        let hint = diamond.querySelector('.spell-empty-hint');
        if (!hint) {
            hint = document.createElement('div');
            hint.className = 'spell-empty-hint';
            diamond.appendChild(hint);
        }
        hint.textContent = 'Libre';
        hint.style.display = 'block';
        hint.style.visibility = 'visible';
        hint.style.opacity = '1';

        if (diamond.classList.contains('locked')) {
            ensureLockOverlay(diamond);
        }

        if (existingCooldown) {
            diamond.appendChild(existingCooldown);
        }
        return;
    }

    const accent = resolveAccent(spell.color || spell.element || spell.type);
    applySpellAccent(diamond, accent);

    if (typeof spell.level === 'number' || typeof spell.levelRatio === 'number') {
        let totalLevel = 0;
        if (typeof spell.level === 'number') {
            totalLevel = normalizeLevel(spell.level);
        } else if (typeof spell.levelRatio === 'number' && typeof spell.maxLevel === 'number') {
            totalLevel = normalizeLevel(spell.levelRatio * spell.maxLevel);
        }
        const ratio = Math.max(0, Math.min(1, totalLevel / MAX_SPELL_LEVEL));
        diamond.style.setProperty('--spell-level-ratio', ratio);
        diamond.style.setProperty('--spell-level-angle', ratio * 360 + 'deg');
        diamond.dataset.totalLevel = totalLevel;
    } else {
        diamond.style.removeProperty('--spell-level-ratio');
        diamond.style.removeProperty('--spell-level-angle');
        diamond.removeAttribute('data-total-level');
    }

    if (spell.icon) {
        diamond.style.setProperty('--spell-icon', `url('${spell.icon}')`);
    } else {
        diamond.style.setProperty('--spell-icon', 'none');
    }

    diamond.classList.add('has-spell', 'has-accent', 'spell-filled');
    diamond.title = spell.name || spell.id || '';

    const nameElement = document.createElement('div');
    nameElement.className = 'spell-name';
    nameElement.textContent = formatSpellName(spell.shortName || spell.name || spell.id || '');
    diamond.appendChild(nameElement);

    if (diamond.classList.contains('locked')) {
        ensureLockOverlay(diamond);
    }

    if (existingCooldown) {
        diamond.appendChild(existingCooldown);
    }
}

function setActiveSpell(id) {
    document.querySelectorAll('.spell-diamond').forEach((s) => {
        s.classList.remove('active');
    });

    if (id) {
        const diamond = document.getElementById(id);
        if (diamond) {
            diamond.classList.add('active');
        }
    }
}

function highlightPosition(position, highlight, highlightType) {
    const allDiamonds = document.querySelectorAll('.spell-diamond');
    allDiamonds.forEach((diamond) => {
        diamond.classList.remove('highlight-position', 'highlight-position-assignment', 'highlight-position-remove');
    });

    if (!highlight || !position) {
        return;
    }

    const diamond = document.getElementById('spell-' + position);
    if (!diamond) {
        return;
    }

    diamond.classList.add('highlight-position');

    if (highlightType === 'assignment') {
        diamond.classList.add('highlight-position-assignment');
    } else if (highlightType === 'remove') {
        diamond.classList.add('highlight-position-remove');
    }
}

function highlightSpell(position, spellId, highlight, highlightType) {
    const allDiamonds = document.querySelectorAll('.spell-diamond');
    allDiamonds.forEach((diamond) => {
        diamond.classList.remove('highlight-spell', 'highlight-spell-selected', 'highlight-spell-remove');
    });

    if (!highlight || !position) {
        return;
    }

    const diamond = document.getElementById('spell-' + position);
    if (!diamond) {
        return;
    }

    diamond.classList.add('highlight-spell');

    if (highlightType === 'selected') {
        diamond.classList.add('highlight-spell-selected');
    } else if (highlightType === 'remove') {
        diamond.classList.add('highlight-spell-remove');
    }
}

function updateCooldown(id, percent) {
    const diamond = document.getElementById(id);
    if (!diamond) {
        return;
    }

    let cooldown = diamond.querySelector('.spell-cooldown');

    if (percent <= 0) {
        diamond.classList.remove('on-cooldown', 'cooldown-blocked');
        if (cooldown) {
            cooldown.remove();
        }
        return;
    }

    diamond.classList.remove('cooldown-blocked');
    
    diamond.classList.add('on-cooldown');

    if (!cooldown) {
        cooldown = createCooldownElement();
        diamond.appendChild(cooldown);
    }

    const progress = 100 - percent;

    const colorLayer = cooldown.querySelector('.spell-cooldown-color');
    if (colorLayer) {
        colorLayer.style.clipPath = getDiamondFillClipPath(progress);
    }

    cooldown.classList.toggle('active', percent > 0 && percent < 100);

    const particles = cooldown.querySelectorAll('.spell-cooldown-particle');
    const lineSum = 200 - 2 * progress;
    particles.forEach((p, i) => {
        const t = (i + 1) / (particles.length + 1);
        let x, y;
        if (progress <= 50) {
            x = 100 - t * (200 - lineSum);
            y = lineSum - x;
        } else {
            x = lineSum * (1 - t);
            y = lineSum * t;
        }
        p.style.left = x + '%';
        p.style.top = y + '%';
    });
}

function getDiamondFillClipPath(progress) {
    if (progress <= 0) {
        return 'polygon(100% 100%, 100% 100%, 100% 100%)';
    }
    if (progress >= 100) {
        return 'polygon(0% 0%, 100% 0%, 100% 100%, 0% 100%)';
    }

    const lineSum = 200 - 2 * progress;

    if (progress <= 50) {
        const yRight = lineSum - 100;
        const xBottom = lineSum - 100;
        return `polygon(100% 100%, 100% ${yRight}%, ${xBottom}% 100%)`;
    } else {
        const xTop = lineSum;
        const yLeft = lineSum;
        return `polygon(100% 100%, 100% 0%, ${xTop}% 0%, 0% ${yLeft}%, 0% 100%)`;
    }
}

function createCooldownElement() {
    const cooldown = document.createElement('div');
    cooldown.className = 'spell-cooldown active';

    const colorLayer = document.createElement('div');
    colorLayer.className = 'spell-cooldown-color';
    cooldown.appendChild(colorLayer);

    const particles = document.createElement('div');
    particles.className = 'spell-cooldown-particles';
    for (let i = 0; i < 8; i++) {
        const particle = document.createElement('div');
        particle.className = 'spell-cooldown-particle';
        particles.appendChild(particle);
    }
    cooldown.appendChild(particles);

    return cooldown;
}

function clearAllCooldowns() {
    const positions = ['top', 'left', 'center', 'right', 'bottom'];
    positions.forEach(pos => {
        const diamond = document.getElementById('spell-' + pos);
        if (diamond) {
            diamond.classList.remove('on-cooldown', 'cooldown-blocked');
            const cooldown = diamond.querySelector('.spell-cooldown');
            if (cooldown) {
                cooldown.remove();
            }
        }
    });
}

function toggleHUD(visible) {
    const hud = document.getElementById('hud');
    if (hud) {
        hud.style.display = visible ? 'block' : 'none';
    }
}

function toggleSpellLock(locked) {
    const diamonds = document.querySelectorAll('.spell-diamond');
    diamonds.forEach((diamond) => {
        diamond.classList.toggle('locked', !!locked);
        if (locked) {
            diamond.classList.remove('selected', 'active');
            diamond.classList.remove(
                'highlight-position',
                'highlight-position-assignment',
                'highlight-position-remove',
                'highlight-spell',
                'highlight-spell-selected',
                'highlight-spell-remove'
            );
            diamond.classList.remove('lock-feedback-active');
            ensureLockOverlay(diamond);
        } else {
            const overlay = diamond.querySelector('.lock-feedback');
            if (overlay) {
                overlay.classList.remove('visible');
            }
            if (lockFeedbackTimers.has(diamond)) {
                clearTimeout(lockFeedbackTimers.get(diamond));
                lockFeedbackTimers.delete(diamond);
            }
            diamond.classList.remove('lock-feedback-active');
        }
    });
}

function toggleMagicDeathOverlay(visible) {
    const overlay = document.getElementById('magic-death-overlay');
    if (!overlay) return;
    if (visible) {
        overlay.classList.add('visible');
    } else {
        overlay.classList.remove('visible');
    }
}

function toggleMagicDeathText(visible) {
    const text = document.getElementById('magic-death-text');
    if (!text) return;
    text.classList.toggle('visible', !!visible);
}

function flashSpell(id) {
    const diamond = document.getElementById(id);
    if (!diamond) return;

    diamond.classList.add('flash');
    setTimeout(() => diamond.classList.remove('flash'), 400);
}

function cooldownBlockedSpell(id) {
    const diamond = document.getElementById(id);
    if (!diamond) return;

    diamond.classList.remove('cooldown-blocked');
    void diamond.offsetWidth;
    diamond.classList.add('cooldown-blocked');
    setTimeout(() => diamond.classList.remove('cooldown-blocked'), 400);
}

function vibrateSpell(id) {
    const diamond = document.getElementById(id);
    if (!diamond) {
        return;
    }

    diamond.classList.add('clicked');
    setTimeout(() => diamond.classList.remove('clicked'), 500);
}

function setSelectedSpell(position, spellId) {
    const allDiamonds = document.querySelectorAll('.spell-diamond');
    allDiamonds.forEach((diamond) => {
        diamond.classList.remove('selected');
    });

    if (!position || !spellId) {
        selectorState.selectedSpellId = null;
        updateGridAssignments();
        return;
    }

    selectorState.selectedSpellId = spellId;
    const diamond = document.getElementById('spell-' + position);
    if (diamond) {
        diamond.classList.add('selected');
    }

    updateGridAssignments();
}

function updateKeys(keys) {
    if (keys && typeof keys === 'object') {
        Object.keys(POSITION_INFO).forEach((position) => {
            if (keys[position] !== undefined && keys[position] !== null) {
                dynamicKeys[position] = String(keys[position]);
            }
        });
    }

    Object.keys(POSITION_INFO).forEach((position) => {
        const diamond = document.getElementById('spell-' + position);
        if (diamond) {
            let keyElement = diamond.querySelector('.spell-key');
            if (!keyElement) {
                keyElement = document.createElement('div');
                keyElement.className = 'spell-key';
                diamond.appendChild(keyElement);
            }
            const keyText = dynamicKeys[position] !== undefined && dynamicKeys[position] !== null
                ? String(dynamicKeys[position])
                : POSITION_INFO[position].key || '';
            keyElement.textContent = keyText;
            diamond.dataset.keyLabel = keyText;
        } else {
            console.warn('[HUD] Losange non trouve pour position:', position);
        }
    });
}

function setMagicHpRegen(regenerating) {
    const barMagic = document.querySelector('.bar-magic');
    if (barMagic) {
        if (regenerating) {
            barMagic.classList.add('regenerating');
        } else {
            barMagic.classList.remove('regenerating');
        }
    }
}

function showMagicHpDamage(damage) {
    const barMagic = document.querySelector('.bar-magic');
    if (barMagic) {
        barMagic.classList.add('damaged');
        setTimeout(() => {
            barMagic.classList.remove('damaged');
        }, 600);
    }

    pulseMagicDamageOverlay(damage);
}

function pulseMagicDamageOverlay(damageAmount) {
    const overlay = document.getElementById('magic-damage-overlay');
    if (!overlay) {
        return;
    }

    const normalized = Math.max(0, Math.min(1, (damageAmount || 0) / 100));
    const opacity = 0.35 + (normalized * 0.45);
    overlay.style.setProperty('--damage-opacity', opacity.toFixed(2));
    overlay.classList.add('active');

    if (magicDamageOverlayTimeout) {
        clearTimeout(magicDamageOverlayTimeout);
    }

    magicDamageOverlayTimeout = setTimeout(() => {
        overlay.classList.remove('active');
    }, 500);
}

function hideMagicDamageOverlay() {
    const overlay = document.getElementById('magic-damage-overlay');
    if (!overlay) {
        return;
    }

    overlay.classList.remove('active');
    overlay.style.removeProperty('--damage-opacity');

    if (magicDamageOverlayTimeout) {
        clearTimeout(magicDamageOverlayTimeout);
        magicDamageOverlayTimeout = null;
    }
}

function normalizeCategory(spell, index) {
    if (spell && spell.category) {
        const cat = String(spell.category).toLowerCase();
        if (['yellow', 'essential', 'utility'].includes(cat)) return 'yellow';
        if (['purple', 'control'].includes(cat)) return 'purple';
        if (['red', 'damage', 'attack'].includes(cat)) return 'red';
        if (['blue', 'force', 'defense'].includes(cat)) return 'blue';
        if (['green', 'transfiguration', 'heal', 'support'].includes(cat)) return 'green';
        return cat;
    }
    if (spell && spell.type) {
        const type = String(spell.type).toLowerCase();
        if (['utility', 'essential'].includes(type)) return 'yellow';
        if (['control'].includes(type)) return 'purple';
        if (['attack', 'damage'].includes(type)) return 'red';
        if (['defense', 'force'].includes(type)) return 'blue';
        if (['heal', 'transfiguration', 'support'].includes(type)) return 'green';
    }
    const row = Math.floor((index || 0) / 4);
    const palette = ['yellow', 'purple', 'red', 'blue', 'green', 'purple', 'red'];
    return palette[row] || 'yellow';
}

function normalizeSpell(spell, index) {
    if (!spell) return null;
    const hasVideo = !!(spell.video || spell.previewVideo);
    const image = hasVideo
        ? (spell.previewImage || spell.image || spell.icon || DEFAULT_PREVIEW_IMAGE)
        : DEFAULT_PREVIEW_IMAGE;
    const category = normalizeCategory(spell, index);
    const accent = resolveAccent(spell.color || spell.element || spell.type || category);
    return {
        id: String(spell.id || spell.name || `spell_${index}`),
        name: spell.name || spell.id || 'Sort',
        shortName: formatSpellName(spell.shortName || spell.name || spell.id),
        description: spell.description || spell.desc || 'Pas de description fournie.',
        icon: spell.icon || spell.image || '',
        image,
        video: spell.video || spell.previewVideo || '',
        category,
        accent,
        available: spell.available !== false
    };
}

function buildGrid() {
    if (!dom.grid) return;
    dom.grid.innerHTML = '';
}

function initFilterMenu() {
    if (!dom.filterToggle || !dom.filterDropdown) return;
    
    dom.filterToggle.addEventListener('click', (e) => {
        e.stopPropagation();
        dom.filterToggle.classList.toggle('open');
        dom.filterDropdown.classList.toggle('open');
    });
    
    document.addEventListener('click', (e) => {
        if (!dom.filterDropdown.contains(e.target) && !dom.filterToggle.contains(e.target)) {
            dom.filterToggle.classList.remove('open');
            dom.filterDropdown.classList.remove('open');
        }
    });
    
    dom.filterDropdown.querySelectorAll('.hl-filter-btn').forEach((btn) => {
        btn.addEventListener('click', (e) => {
            e.stopPropagation();
            const filter = btn.dataset.filter;
            setActiveFilter(filter);
        });
    });
}

function setActiveFilter(filter) {
    selectorState.activeFilter = filter;
    
    dom.filterDropdown.querySelectorAll('.hl-filter-btn').forEach((btn) => {
        btn.classList.toggle('active', btn.dataset.filter === filter);
    });
    
    renderSpellGrid();
    
    dom.filterToggle.classList.remove('open');
    dom.filterDropdown.classList.remove('open');
}

function getFilteredSpells() {
    const base = selectorState.activeFilter === 'all'
        ? selectorState.spells
        : selectorState.spells.filter(spell => spell && spell.category === selectorState.activeFilter);
    const q = String(selectorState.searchQuery || '').trim().toLowerCase();
    if (!q) return base;
    return base.filter(spell => {
        const name = String(spell.name || '').toLowerCase();
        const shortName = String(spell.shortName || '').toLowerCase();
        return name.includes(q) || shortName.includes(q);
    });
}

function wireHudSlots() {
    document.querySelectorAll('.spell-diamond').forEach((slot) => {
        slot.addEventListener('click', handleLockedDiamondClick);
    });
}

function handleCardMouseDown(event) {
    const card = event.currentTarget;
    const spellId = card.dataset.spellId;
    if (!spellId || card.classList.contains('empty') || card.classList.contains('unavailable')) {
        return;
    }
    
    event.preventDefault();
    selectorState.isDragging = true;
    selectorState.draggingSpellId = spellId;
    selectorState.dragElement = card;
    
    const rect = card.getBoundingClientRect();
    selectorState.dragOffset.x = event.clientX - rect.left;
    selectorState.dragOffset.y = event.clientY - rect.top;
    
    card.classList.add('dragging');
    
    const clone = card.cloneNode(true);
    clone.id = 'drag-ghost';
    clone.style.position = 'fixed';
    clone.style.pointerEvents = 'none';
    clone.style.zIndex = '10000';
    clone.style.opacity = '0.7';
    clone.style.width = rect.width + 'px';
    clone.style.height = rect.height + 'px';
    clone.style.left = (event.clientX - selectorState.dragOffset.x) + 'px';
    clone.style.top = (event.clientY - selectorState.dragOffset.y) + 'px';
    document.body.appendChild(clone);
    
    document.addEventListener('mousemove', handleCardMouseMove);
    document.addEventListener('mouseup', handleCardMouseUp);
}

function handleCardMouseMove(event) {
    if (!selectorState.isDragging || !selectorState.dragElement) return;
    
    const ghost = document.getElementById('drag-ghost');
    if (ghost) {
        ghost.style.left = (event.clientX - selectorState.dragOffset.x) + 'px';
        ghost.style.top = (event.clientY - selectorState.dragOffset.y) + 'px';
    }
    
    const elementBelow = document.elementFromPoint(event.clientX, event.clientY);
    const slot = elementBelow ? elementBelow.closest('.hl-slot-diamond') : null;
    
    document.querySelectorAll('.hl-slot-diamond').forEach((s) => {
        s.classList.remove('drag-over');
    });
    
    if (slot) {
        slot.classList.add('drag-over');
    }
}

function handleCardMouseUp(event) {
    if (!selectorState.isDragging) return;
    
    const ghost = document.getElementById('drag-ghost');
    if (ghost) {
        ghost.remove();
    }
    
    if (selectorState.dragElement) {
        selectorState.dragElement.classList.remove('dragging');
    }
    
    const elementBelow = document.elementFromPoint(event.clientX, event.clientY);
    const slot = elementBelow ? elementBelow.closest('.hl-slot-diamond') : null;
    
    if (slot && selectorState.draggingSpellId) {
        const position = slot.dataset.position;
        if (position && ['top', 'left', 'center', 'right', 'bottom'].includes(position)) {
            assignSpellToSlot(selectorState.draggingSpellId, position);
        }
    }
    
    document.querySelectorAll('.hl-slot-diamond').forEach((s) => {
        s.classList.remove('drag-over');
    });
    
    selectorState.isDragging = false;
    selectorState.draggingSpellId = null;
    selectorState.dragElement = null;
    
    document.removeEventListener('mousemove', handleCardMouseMove);
    document.removeEventListener('mouseup', handleCardMouseUp);
}


function setSpellbook(spells) {
    selectorState.spellLookup.clear();
    selectorState.spells = Array.isArray(spells)
        ? spells.map((spell, index) => normalizeSpell(spell, index)).filter(Boolean)
        : [];
    selectorState.spells.sort((a, b) => {
        const an = (a.name || a.id || '').toLowerCase();
        const bn = (b.name || b.id || '').toLowerCase();
        if (an === bn) {
            return (a.id || '').toLowerCase() < (b.id || '').toLowerCase();
        }
        return an < bn;
    });
    selectorState.spells.forEach((spell) => selectorState.spellLookup.set(spell.id, spell));
    renderSpellGrid();
}

function isSpellAssigned(spellId) {
    return Object.values(selectorState.slotAssignments).some((spell) => spell && spell.id === spellId);
}

function renderSpellGrid() {
    if (!dom.grid) return;
    const filteredSpells = getFilteredSpells();
    dom.grid.innerHTML = '';
    const order = ['yellow', 'red', 'purple', 'blue', 'green'];
    const groups = {};
    filteredSpells.forEach(spell => {
        if (!spell) return;
        const cat = spell.category || 'yellow';
        if (!groups[cat]) groups[cat] = [];
        groups[cat].push(spell);
    });
    const cats = order.filter(cat => groups[cat] && groups[cat].length > 0);
    const list = document.createElement('div');
    list.className = 'hl-category-spells';
    let spellsCount = 0;
    cats.forEach(cat => {
        groups[cat].forEach(spell => {
            const card = document.createElement('div');
            card.className = 'hl-spell-card';
            card.dataset.spellId = spell.id;
            card.classList.add(`hl-category-${spell.category}`);
            card.setAttribute('draggable', 'false');
            card.draggable = false;
            if (spell.available !== false) {
                card.addEventListener('mousedown', handleCardMouseDown, false);
            } else {
                card.classList.add('unavailable');
            }
            card.addEventListener('mouseenter', handleCardHover);
            card.addEventListener('click', handleCardClick);
            const icon = document.createElement('div');
            icon.className = 'hl-spell-icon';
            icon.style.pointerEvents = 'none';
            icon.draggable = false;
            if (spell.icon) {
                icon.style.backgroundImage = `url('${spell.icon}')`;
            }
            const label = document.createElement('div');
            label.className = 'hl-spell-label';
            label.textContent = spell.shortName;
            label.style.pointerEvents = 'none';
            label.draggable = false;
            card.appendChild(icon);
            card.appendChild(label);
            const assignedSpell = Object.values(selectorState.slotAssignments).find(s => s && s.id === spell.id);
            if (assignedSpell && (assignedSpell.level !== undefined || assignedSpell.levelRatio !== undefined)) {
                let totalLevel = 0;
                if (typeof assignedSpell.level === 'number') {
                    totalLevel = normalizeLevel(assignedSpell.level);
                } else if (typeof assignedSpell.levelRatio === 'number' && typeof assignedSpell.maxLevel === 'number') {
                    totalLevel = normalizeLevel(assignedSpell.levelRatio * assignedSpell.maxLevel);
                }
                if (totalLevel > 0) {
                    const levelInfo = formatLevel(totalLevel);
                    card.title = `${spell.name || spell.id}\n${levelInfo.label}`;
                } else {
                    card.title = spell.name || spell.id;
                }
            } else {
                card.title = spell.name || spell.id;
            }
            if (isSpellAssigned(spell.id)) {
                card.classList.add('assigned');
            }
            if (spell.id === selectorState.selectedSpellId) {
                card.classList.add('selected');
            }
            list.appendChild(card);
            spellsCount += 1;
        });
    });
    const columns = 6;
    const extraRows = 1;
    const placeholders = (Math.ceil(spellsCount / columns) + extraRows) * columns - spellsCount;
    for (let i = 0; i < placeholders; i++) {
        const empty = document.createElement('div');
        empty.className = 'hl-spell-card empty';
        empty.setAttribute('draggable', 'false');
        empty.draggable = false;
        list.appendChild(empty);
    }
    dom.grid.appendChild(list);
}

function updateGridAssignments() {
    if (!dom.grid) return;
    dom.grid.querySelectorAll('.hl-spell-card').forEach((card) => {
        const spellId = card.dataset.spellId;
        card.classList.remove('assigned', 'selected');
        if (spellId && isSpellAssigned(spellId)) {
            card.classList.add('assigned');
        }
        if (spellId && spellId === selectorState.selectedSpellId) {
            card.classList.add('selected');
        }
    });
}

function showPreview(spellId) {
    const spell = selectorState.spellLookup.get(spellId);
    if (!spell || spell.available === false) {
        resetPreview();
        return;
    }

    const assignedSpell = Object.values(selectorState.slotAssignments).find(s => s && s.id === spellId);
    let levelInfo = '';
    if (assignedSpell && (assignedSpell.level !== undefined || assignedSpell.levelRatio !== undefined)) {
        let totalLevel = 0;
        if (typeof assignedSpell.level === 'number') {
            totalLevel = normalizeLevel(assignedSpell.level);
        } else if (typeof assignedSpell.levelRatio === 'number' && typeof assignedSpell.maxLevel === 'number') {
            totalLevel = normalizeLevel(assignedSpell.levelRatio * assignedSpell.maxLevel);
        }
        if (totalLevel > 0) {
            const info = formatLevel(totalLevel);
            levelInfo = `\n\n${info.label}`;
        }
    }

    if (dom.previewTitle) {
        dom.previewTitle.textContent = spell.name || spell.id;
    }
    if (dom.previewDescription) {
        dom.previewDescription.textContent = (spell.description || 'Pas de description fournie.') + levelInfo;
    }

    if (dom.previewPlaceholder) {
        dom.previewPlaceholder.style.display = 'none';
    }

    if (dom.previewVideo) {
        dom.previewVideo.style.display = 'none';
    }
    if (dom.previewImage) {
        dom.previewImage.style.display = 'none';
    }

    if (spell.video && dom.previewVideo) {
        dom.previewVideo.src = spell.video;
        dom.previewVideo.style.display = 'block';
        dom.previewVideo.play().catch(() => {});
    } else if (dom.previewImage) {
        const imageSrc = spell.video
            ? (spell.image || DEFAULT_PREVIEW_IMAGE)
            : DEFAULT_PREVIEW_IMAGE;
        dom.previewImage.src = imageSrc;
        dom.previewImage.style.display = 'block';
    } else if (dom.previewPlaceholder) {
        dom.previewPlaceholder.style.display = 'flex';
    }
}

function resetPreview() {
    if (dom.previewTitle) dom.previewTitle.textContent = '';
    if (dom.previewDescription) dom.previewDescription.textContent = '';
    if (dom.previewPlaceholder) dom.previewPlaceholder.style.display = 'flex';
    if (dom.previewVideo) dom.previewVideo.style.display = 'none';
    if (dom.previewImage) dom.previewImage.style.display = 'none';
}

function assignSpellToSlot(spellId, position) {
    if (!spellId || !position) return;
    const spell = selectorState.spellLookup.get(spellId) || normalizeSpell({ id: spellId, name: spellId }, selectorState.spells.length);
    selectorState.slotAssignments[position] = spell;
    setSpell(position, spell);
    updateGridAssignments();
    
    const positionToKeyIndex = {
        'top': 1,
        'left': 2,
        'right': 3,
        'center': 4,
        'bottom': 5
    };
    const keyIndex = positionToKeyIndex[position];
    if (keyIndex) {
        postNui('assignSpell', { spellId, keyIndex });
    }
}

function unassignSpellFromSlot(position) {
    if (!position) return;
    const spell = selectorState.slotAssignments[position];
    if (!spell) return;

    selectorState.slotAssignments[position] = null;
    if (selectorState.selectedSpellId === spell.id) {
        selectorState.selectedSpellId = null;
        resetPreview();
    }
    updateHlSlots();
    updateGridAssignments();
    postNui('unassignSpell', { position, spellId: spell.id });
}

function updateHlSlots() {
    document.querySelectorAll('.hl-slot-diamond').forEach((slot) => {
        const position = slot.dataset.position;
        const spell = selectorState.slotAssignments[position];
        
        slot.innerHTML = '';
        slot.classList.remove('has-spell', 'has-accent', 'spell-filled', 'spell-empty');
        slot.style.removeProperty('--spell-icon');
        slot.style.removeProperty('--spell-accent');
        slot.style.removeProperty('--spell-accent-rgb');
        slot.style.removeProperty('--spell-level-ratio');
        slot.style.removeProperty('--spell-level-angle');
        
        buildBaseSlotSkeleton(slot, position);
        slot.oncontextmenu = (event) => {
            event.preventDefault();
            unassignSpellFromSlot(position);
            return false;
        };
        
        if (!spell) {
            slot.classList.add('spell-empty');
            slot.style.setProperty('--spell-icon', 'none');
            
            const hint = document.createElement('div');
            hint.className = 'spell-empty-hint';
            hint.textContent = 'Libre';
            slot.appendChild(hint);
            return;
        }
        
        slot.dataset.spellId = spell.id;
        slot.classList.add('has-spell', 'has-accent', 'spell-filled');
        
        const accent = resolveAccent(spell.color || spell.element || spell.type);
        applySpellAccent(slot, accent);
        
        if (typeof spell.level === 'number' || typeof spell.levelRatio !== undefined) {
            let totalLevel = 0;
            if (typeof spell.level === 'number') {
                totalLevel = normalizeLevel(spell.level);
            } else if (typeof spell.levelRatio === 'number' && typeof spell.maxLevel === 'number') {
                totalLevel = normalizeLevel(spell.levelRatio * spell.maxLevel);
            } else if (typeof spell.levelRatio === 'number') {
                totalLevel = normalizeLevel(spell.levelRatio * MAX_SPELL_LEVEL);
            }
            const ratio = Math.max(0, Math.min(1, totalLevel / MAX_SPELL_LEVEL));
            slot.style.setProperty('--spell-level-ratio', ratio);
            slot.style.setProperty('--spell-level-angle', ratio * 360 + 'deg');
            slot.dataset.totalLevel = totalLevel;
        }
        
        if (spell.icon) {
            slot.style.setProperty('--spell-icon', `url('${spell.icon}')`);
        } else {
            slot.style.setProperty('--spell-icon', 'none');
        }
        
        slot.title = spell.name || spell.id || '';

        const nameElement = document.createElement('div');
        nameElement.className = 'spell-name';
        nameElement.textContent = formatSpellName(spell.shortName || spell.name || spell.id || '');
        slot.appendChild(nameElement);
    });
}

const spellSetsState = {
    sets: [],
    currentSetId: 1,
    maxSets: 5,
    isLoading: false,
    isSwitching: false,
    scrollInitialized: false
};

function loadSpellSets() {
    if (spellSetsState.isLoading) return;
    spellSetsState.isLoading = true;

    fetch(`https://${resourceName}/getSpellSets`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    })
    .then(response => response.text())
    .then(text => {
        let sets = [];
        try {
            let parsed = JSON.parse(text);
            if (typeof parsed === 'string') {
                parsed = JSON.parse(parsed);
            }
            if (Array.isArray(parsed)) {
                sets = parsed;
            }
        } catch (e) {
            console.error('[SpellSets] Parse error:', e);
        }
        spellSetsState.sets = sets;
        const activeSet = sets.find(s => s.active);
        spellSetsState.currentSetId = activeSet?.id || 1;
        updateSpellSetsIndicator();
    })
    .catch(err => {
        console.error('[SpellSets] Failed to load:', err);
        updateSpellSetsIndicator();
    })
    .finally(() => {
        spellSetsState.isLoading = false;
    });
}

function updateSpellSetsIndicator() {
    const selectorDots = document.querySelectorAll('.hl-spell-set-dot');
    selectorDots.forEach(dot => {
        const setId = parseInt(dot.dataset.set);
        dot.classList.toggle('active', setId === spellSetsState.currentSetId);
    });

    const hudDots = document.querySelectorAll('.hud-spell-set-dot');
    hudDots.forEach(dot => {
        const setId = parseInt(dot.dataset.set);
        dot.classList.toggle('active', setId === spellSetsState.currentSetId);
    });
}

function switchSpellSetWithAnimation(setId, direction) {
    if (setId < 1 || setId > spellSetsState.maxSets) return;
    if (setId === spellSetsState.currentSetId) return;
    if (spellSetsState.isSwitching) return;

    spellSetsState.isSwitching = true;

    const slotsGrid = document.querySelector('.hl-slots-grid');
    if (!slotsGrid) {
        spellSetsState.currentSetId = setId;
        updateSpellSetsIndicator();
        postNui('switchSpellSet', { setId: setId });
        spellSetsState.isSwitching = false;
        return;
    }

    const outClass = direction === 'up' ? 'switching-up' : 'switching-down';
    const inClass = direction === 'up' ? 'switching-in-up' : 'switching-in-down';

    slotsGrid.classList.add(outClass);

    setTimeout(() => {
        spellSetsState.currentSetId = setId;
        updateSpellSetsIndicator();
        postNui('switchSpellSet', { setId: setId });

        if (Array.isArray(spellSetsState.sets)) {
            spellSetsState.sets.forEach(s => {
                s.active = s.id === setId;
            });
        }

        slotsGrid.classList.remove(outClass);
        slotsGrid.classList.add(inClass);

        setTimeout(() => {
            slotsGrid.classList.remove(inClass);
            spellSetsState.isSwitching = false;
        }, 300);
    }, 300);
}

function nextSpellSet() {
    let newId = spellSetsState.currentSetId + 1;
    if (newId > spellSetsState.maxSets) {
        newId = 1;
    }
    switchSpellSetWithAnimation(newId, 'up');
}

function prevSpellSet() {
    let newId = spellSetsState.currentSetId - 1;
    if (newId < 1) {
        newId = spellSetsState.maxSets;
    }
    switchSpellSetWithAnimation(newId, 'down');
}

function handleSlotsScroll(event) {
    if (!selectorState.visible) return;
    if (spellSetsState.isSwitching) return;

    const slotsContainer = document.querySelector('.hl-slots-container');
    if (!slotsContainer) return;

    if (!slotsContainer.contains(event.target) && event.target !== slotsContainer) return;

    event.preventDefault();

    if (event.deltaY > 0) {
        nextSpellSet();
    } else if (event.deltaY < 0) {
        prevSpellSet();
    }
}

function initSpellSetsControls() {
    if (spellSetsState.scrollInitialized) return;

    const slotsContainer = document.querySelector('.hl-slots-container');
    if (slotsContainer) {
        slotsContainer.addEventListener('wheel', handleSlotsScroll, { passive: false });
        spellSetsState.scrollInitialized = true;
    }

    const dots = document.querySelectorAll('.hl-spell-set-dot');
    dots.forEach(dot => {
        dot.addEventListener('click', () => {
            const setId = parseInt(dot.dataset.set);
            if (setId && setId !== spellSetsState.currentSetId) {
                const direction = setId > spellSetsState.currentSetId ? 'up' : 'down';
                switchSpellSetWithAnimation(setId, direction);
            }
        });
    });
}

function openSpellSelector(payload) {
    selectorState.visible = true;
    if (payload && Array.isArray(payload.spells)) {
        setSpellbook(payload.spells);
    }
    if (payload && payload.assignments) {
        Object.keys(payload.assignments).forEach((pos) => {
            const spellData = payload.assignments[pos];
            if (spellData) {
                selectorState.slotAssignments[pos] = spellData;
            }
        });
    }
    if (dom.selector) {
        dom.selector.classList.add('active');
    }
    document.body.classList.add('selector-open');
    if (dom.hud) {
        dom.hud.classList.add('interactive');
    }
    if (dom.searchInput) {
        setTimeout(() => {
            dom.searchInput.focus();
        }, 0);
    }
    renderSpellGrid();
    updateHlSlots();
    initSpellSetsControls();
    loadSpellSets();
}

function closeSpellSelector() {
    selectorState.visible = false;
    selectorState.isDragging = false;
    selectorState.draggingSpellId = null;
    selectorState.dragElement = null;
    
    const ghost = document.getElementById('drag-ghost');
    if (ghost) {
        ghost.remove();
    }
    
    document.removeEventListener('mousemove', handleCardMouseMove);
    document.removeEventListener('mouseup', handleCardMouseUp);
    
    if (dom.selector) {
        dom.selector.classList.remove('active');
    }
    document.body.classList.remove('selector-open');
    if (dom.hud) {
        dom.hud.classList.remove('interactive');
    }
    postNui('closeSpellSelector', {});
}

function handleCardHover(event) {
    const spellId = event.currentTarget.dataset.spellId;
    if (spellId) {
        showPreview(spellId);
    }
}

function handleCardClick(event) {
    const spellId = event.currentTarget.dataset.spellId;
    if (!spellId) return;
    
    selectorState.selectedSpellId = spellId;
    updateGridAssignments();
    showPreview(spellId);
}

function handleMessage(event) {
    const data = event.data;

    switch (data.action) {
        case 'updateHealth':
            updateBar('bar-health-fill', data.value);
            break;
        case 'updateHunger':
            updateBar('bar-blue-fill', data.value);
            break;
        case 'updateThirst':
            updateBar('bar-green-fill', data.value);
            break;
        case 'updateMagicHp':
            updateBar('bar-magic-fill', data.value);
            break;
        case 'setMagicHpRegen':
            setMagicHpRegen(data.regenerating);
            break;
        case 'magicHpDamage':
            showMagicHpDamage(data.damage);
            break;
        case 'hideMagicDamageOverlay':
            hideMagicDamageOverlay();
            break;
        case 'updatePotion':
            updateBar('bar-potion-fill', data.value);
            break;
        case 'updateBars':
            if (data.health !== undefined) updateBar('bar-health-fill', data.health);
            if (data.hunger !== undefined) updateBar('bar-green-fill', data.hunger);
            if (data.thirst !== undefined) updateBar('bar-blue-fill', data.thirst);
            if (data.potion !== undefined) updateBar('bar-potion-fill', data.potion);
            if (data.magicHp !== undefined) updateBar('bar-magic-fill', data.magicHp);
            if (data.healthCurrent !== undefined || data.healthMax !== undefined) {
                updateHealthText(data.healthCurrent, data.healthMax);
            }
            break;
        case 'setSpell':
            setSpell(data.position, data.spell);
            selectorState.slotAssignments[data.position] = data.spell;
            updateGridAssignments();
            updateHlSlots();
            initializeEmptySlots();
            break;
        case 'highlightPosition':
            highlightPosition(data.position, data.highlight, data.highlightType);
            break;
        case 'highlightSpell':
            highlightSpell(data.position, data.spellId, data.highlight, data.highlightType);
            break;
        case 'setSelectedSpell':
            setSelectedSpell(data.position, data.spellId);
            break;
        case 'setActiveSpell':
            setActiveSpell(data.id);
            break;
        case 'updateCooldown':
            updateCooldown(data.id, data.percent);
            break;
        case 'clearAllCooldowns':
            clearAllCooldowns();
            break;
        case 'toggleHUD':
            toggleHUD(data.visible);
            break;
        case 'toggleSpellLock':
            toggleSpellLock(data.locked);
            break;
        case 'flashSpell':
            flashSpell(data.id);
            break;
        case 'vibrateSpell':
            vibrateSpell(data.id);
            break;
        case 'cooldownBlocked':
            cooldownBlockedSpell(data.id);
            break;
        case 'updateKeys':
            updateKeys(data.keys);
            break;
        case 'showMagicDeathOverlay':
            toggleMagicDeathOverlay(data.visible);
            break;
        case 'showMagicDeathText':
            toggleMagicDeathText(data.visible);
            break;
        case 'openSpellSelector':
            openSpellSelector(data);
            break;
        case 'closeSpellSelector':
            closeSpellSelector();
            break;
        case 'toggleSpellSelector':
            if (data.visible) {
                openSpellSelector(data);
            } else {
                closeSpellSelector();
            }
            break;
        case 'setSpellbook':
        case 'updateSpellList':
            setSpellbook(data.spells || []);
            initializeEmptySlots();
            break;
        case 'updateSpellSetIndicator':
            if (data.setId) {
                spellSetsState.currentSetId = data.setId;
                updateSpellSetsIndicator();
            }
            break;
        case 'openProfessorMenu':
            openProfessorMenu(data);
            break;
        case 'closeProfessorMenu':
            closeProfessorMenu();
            break;
        case 'professorNearbyPlayers':
            renderNearbyStudents(data.players || []);
            renderBulkPoints();
            break;
        case 'professorAllSpells':
            professorState.allSpells = data.spells || [];
            professorState.allSpellsRef = professorState.allSpells;
            renderAllSpells();
            break;
        case 'professorAllPlayers':
            professorState.allPlayers = data.players || [];
            professorState.allPlayersRef = professorState.allPlayers;
            renderAllPlayers();
            break;
        case 'professorPlayerSkillPoints':
            if (data.playerId && professorState.selectedPlayer && professorState.selectedPlayer.id === data.playerId) {
                const pts = typeof data.points === 'number' ? data.points : 0;
                professorState.selectedPlayer.skillPoints = pts;
                if (professorDOM.playerSkillpoints) {
                    professorDOM.playerSkillpoints.textContent = `Points compétence : ${pts}`;
                }
            }
            break;
        case 'professorPlayerSkillLevels':
            if (data.playerId) {
                if (professorState.selectedPlayer && professorState.selectedPlayer.id === data.playerId) {
                    professorState.selectedPlayer.skills = data.levels || [];
                    if (typeof data.availablePoints === 'number') {
                        professorState.selectedPlayer.skillPoints = data.availablePoints;
                        if (professorDOM.playerSkillpoints) {
                            professorDOM.playerSkillpoints.textContent = `Points compétence : ${data.availablePoints}`;
                        }
                    }
                }
                if (professorState.pendingRemoveSkill && professorState.pendingRemoveSkill.playerId === data.playerId) {
                    const playerName = professorState.pendingRemoveSkill.playerName || `ID ${data.playerId}`;
                    showRemoveSkillModal(data.playerId, playerName, data.levels || [], data.availablePoints);
                    professorState.pendingRemoveSkill = null;
                }
            }
            break;
        case 'professorPlayerSpells':
            if (!data.playerId || (professorState.selectedPlayer && professorState.selectedPlayer.id === data.playerId)) {
                renderPlayerSpells(data.spells || {});
            }
            break;
        case 'professorTempSpells':
            professorState.tempSpells.clear();
            
            if (data.tempSpells) {
                Object.entries(data.tempSpells).forEach(([playerIdStr, spells]) => {
                    const playerId = parseInt(playerIdStr, 10);
                    if (!isNaN(playerId) && playerId > 0 && spells) {
                        if (!professorState.tempSpells.has(playerId)) {
                            professorState.tempSpells.set(playerId, new Map());
                        }
                        
                        Object.entries(spells).forEach(([spellId, level]) => {
                            professorState.tempSpells.get(playerId).set(spellId, normalizeLevel(level || 0));
                        });
                    }
                });
            }
            
            renderTempSpells();
            break;
        case 'professorSpellAction':
            handleProfessorSpellAction(data);
            break;
        default:
            break;
    }
}

function handleProfessorSpellAction(data) {
    const { actionType, playerName, spellName, success, playerId, spellId, isTemporary, level } = data;
    
    if (professorState.massAction) {
        return;
    }

    if (success) {
        if (spellId === 'skill_point_remove' || actionType === 'Retrait point') {
            professorNotify('success', 'Succès', `${spellName} retiré à ${playerName}`);
        } else {
            professorNotify('success', 'Succès', `${actionType} : ${spellName} attribué à ${playerName}`);
        }
        
        if ((actionType === 'Attribution' || actionType === 'Modification') && isTemporary) {
            const actionKey = `${playerId}_${spellId}`;
            const pendingAction = professorState.pendingSpellActions.get(actionKey);
            
            const finalLevel = level !== undefined ? level : (pendingAction?.level !== undefined ? pendingAction.level : (data.level !== undefined ? data.level : 0));
            
            if (pendingAction) {
                if (!professorState.tempSpells.has(pendingAction.playerId)) {
                    professorState.tempSpells.set(pendingAction.playerId, new Map());
                }
                professorState.tempSpells.get(pendingAction.playerId).set(pendingAction.spellId, finalLevel);
                professorState.pendingSpellActions.delete(actionKey);
                renderTempSpells();
                refreshNearbyPlayers();
            } else {
                if (!professorState.tempSpells.has(playerId)) {
                    professorState.tempSpells.set(playerId, new Map());
                }
                professorState.tempSpells.get(playerId).set(spellId, finalLevel);
                renderTempSpells();
                refreshNearbyPlayers();
            }
        }
        
        addToHistory(actionType, playerName, spellName);
    } else {
        if (professorState.massAction) {
            return;
        }
        if (playerId && spellId) {
            const actionKey = `${playerId}_${spellId}`;
            professorState.pendingSpellActions.delete(actionKey);
        } else {
            for (const [key, action] of professorState.pendingSpellActions.entries()) {
                const player = professorState.nearbyPlayers.find(p => p.id === action.playerId) ||
                              professorState.allPlayers.find(p => p.id === action.playerId);
                if (player && player.name === playerName) {
                    professorState.pendingSpellActions.delete(key);
                    break;
                }
            }
        }
        
        let errorMsg = '';
        if (actionType === 'Attribution') {
            if (playerName === 'Joueur') {
                errorMsg = 'Joueur introuvable';
            } else {
                errorMsg = `${spellName} est déjà possédé par ${playerName} ou une erreur est survenue`;
            }
        } else {
            errorMsg = `Échec de ${actionType} pour ${spellName}`;
        }
        professorNotify('error', 'Erreur', errorMsg);
    }
}

function testMode() {
    const sampleSpells = Array.from({ length: 28 }, (_, i) => ({
            id: `spell_${i + 1}`,
        name: `Sort ${i + 1}`,
        description: 'Description de démonstration inspirée de Hogwarts Legacy.',
        category: normalizeCategory({}, i),
        icon: '',
        image: '',
        video: ''
    }));
    setSpellbook(sampleSpells);
    setSpell('top', sampleSpells[0]);
    setSpell('left', sampleSpells[1]);
    setSpell('right', sampleSpells[2]);
    setSpell('center', sampleSpells[3]);
    setSpell('bottom', sampleSpells[4]);
    toggleHUD(true);
    openSpellSelector({});
}

function initializeEmptySlots() {
    const positions = ['top', 'left', 'center', 'right', 'bottom'];
    positions.forEach(position => {
        const diamond = document.getElementById('spell-' + position);
        if (diamond) {
            const spellId = diamond.dataset.spellId;
            if (!spellId || spellId === '' || spellId === 'null' || spellId === 'undefined') {
                if (!diamond.classList.contains('spell-empty')) {
                    diamond.classList.add('spell-empty');
                }
                
                let hint = diamond.querySelector('.spell-empty-hint');
                if (!hint) {
                    hint = document.createElement('div');
                    hint.className = 'spell-empty-hint';
                    diamond.appendChild(hint);
                }
                hint.textContent = 'Libre';
                hint.style.display = 'block';
                hint.style.visibility = 'visible';
                hint.style.opacity = '1';
            }
        }
    });
}

window.addEventListener('DOMContentLoaded', () => {
    buildGrid();
    initFilterMenu();
    if (dom.searchInput) {
        dom.searchInput.addEventListener('input', (e) => {
            selectorState.searchQuery = String(e.target.value || '').trim();
            renderSpellGrid();
        });
    }
    wireHudSlots();
    initializeLockHandlers();
    initializeEmptySlots();

    postNui('hudReady', {});

    if (window.location.protocol === 'file:') {
        testMode();
    }
});


window.addEventListener('message', handleMessage);

document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape' && selectorState.visible) {
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
        closeSpellSelector();
        return false;
    }
}, true);

document.addEventListener('keydown', function(event) {
    if (!selectorState.visible || !dom.searchInput) return;
    const target = event.target;
    const isTypingTarget = target === dom.searchInput
        || (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA'))
        || (target && target.isContentEditable);
    if (isTypingTarget) return;
    if (event.ctrlKey || event.altKey || event.metaKey) return;
    const key = event.key;
    const isLetterOrSpace = key && key.length === 1 && /[A-Za-zÀ-ÿ ]/.test(key);
    if (!isLetterOrSpace) return;
    event.preventDefault();
    dom.searchInput.focus();
    const start = dom.searchInput.selectionStart ?? dom.searchInput.value.length;
    const end = dom.searchInput.selectionEnd ?? dom.searchInput.value.length;
    const before = dom.searchInput.value.slice(0, start);
    const after = dom.searchInput.value.slice(end);
    dom.searchInput.value = before + key + after;
    const newPos = start + 1;
    dom.searchInput.selectionStart = newPos;
    dom.searchInput.selectionEnd = newPos;
    selectorState.searchQuery = String(dom.searchInput.value || '').trim();
    renderSpellGrid();
}, false);

document.addEventListener('click', function(event) {
    if (!selectorState.visible) return;
    const selector = document.getElementById('spell-selector');
    if (selector && !selector.contains(event.target)) {
        closeSpellSelector();
    }
}, true);

const professorState = {
    visible: false,
    currentTab: 'course',
    allSpells: [],
    allSpellsRef: null,
    allPlayers: [],
    allPlayersRef: null,
    nearbyPlayers: [],
    selectedPlayer: null,
    selectedPlayerSpells: {},
    tempSpells: new Map(),
    pendingSpellActions: new Map(),
    professor: null,
    expandedPlayers: new Set(),
    massAction: null,
    canManageSpells: true,
    pendingRemoveSkill: null
};

const professorDOM = {
    menu: document.getElementById('professor-menu'),
    closeBtn: document.getElementById('professor-close-btn'),
    tabs: document.querySelectorAll('.professor-tab'),
    tabContents: document.querySelectorAll('.professor-panel'),
    nearbyStudentsList: document.getElementById('nearby-students-list'),
    refreshNearbyBtn: document.getElementById('refresh-nearby-btn'),
    includeProfessorBtn: document.getElementById('include-professor-btn'),
    removeAllTempBtn: document.getElementById('remove-all-temp-btn'),
    tempSpellsList: document.getElementById('temp-spells-list'),
    allSpellsGrid: document.getElementById('all-spells-grid'),
    spellSearch: document.getElementById('spell-search'),
    playersList: document.getElementById('players-list'),
    playerSearch: document.getElementById('player-search'),
    playerDetailsSection: document.getElementById('player-details-section'),
    selectedPlayerName: document.getElementById('selected-player-name'),
    addSpellPermanentBtn: document.getElementById('add-spell-permanent-btn'),
    giveSkillpointBtn: document.getElementById('give-skillpoint-btn'),
    removeSkillpointBtn: document.getElementById('remove-skillpoint-btn'),
    addAllPermanentBtn: document.getElementById('add-all-permanent-btn'),
    applyGlobalLevelsBtn: document.getElementById('apply-global-levels-btn'),
    globalLevelInput: document.getElementById('global-level-input'),
    playerSpellsList: document.getElementById('player-spells-list'),
    playerSpellSearch: document.getElementById('player-spell-search'),
    removeAllPermanentBtn: document.getElementById('remove-all-permanent-btn'),
    setMaxLevelBtn: document.getElementById('set-max-level-btn'),
    resetCooldownBtn: document.getElementById('reset-cooldown-btn'),
    playerSkillpoints: document.getElementById('player-skillpoints'),
    bulkPanel: document.getElementById('points-bulk-panel'),
    bulkRefreshBtn: document.getElementById('bulk-refresh-btn'),
    bulkGiveBtn: document.getElementById('bulk-give-btn'),
    bulkAmountInput: document.getElementById('bulk-points-amount'),
    bulkList: document.getElementById('bulk-points-list'),
    bulkSelectedCount: document.getElementById('bulk-selected-count'),
    modalLayer: document.getElementById('modal-layer'),
    notificationsContainer: document.getElementById('professor-notifications')
};

function renderBulkPoints() {
    if (!professorDOM.bulkList) return;
    const players = professorState.nearbyPlayers || [];
    if (players.length === 0) {
        professorDOM.bulkList.innerHTML = '<div class="empty-state">Aucun élève à proximité (10m)</div>';
        if (professorDOM.bulkSelectedCount) professorDOM.bulkSelectedCount.textContent = '0 sélectionné(s)';
        return;
    }

    professorDOM.bulkList.innerHTML = players.map(player => `
        <label class="list-row">
            <div class="card-main">
                <input type="checkbox" class="bulk-check" data-player-id="${player.id}" style="margin-right: 8px;">
                <div>
                    <div class="title">${sanitizePlayerName(player)}</div>
                    <div class="muted">ID ${player.id}</div>
                </div>
            </div>
            <span class="muted">${player.distance ? `${player.distance.toFixed(1)} m` : ''}</span>
        </label>
    `).join('');

    const updateCount = () => {
        const checked = professorDOM.bulkList.querySelectorAll('.bulk-check:checked').length;
        if (professorDOM.bulkSelectedCount) professorDOM.bulkSelectedCount.textContent = `${checked} sélectionné(s)`;
    };

    professorDOM.bulkList.querySelectorAll('.bulk-check').forEach(cb => {
        cb.addEventListener('change', updateCount);
    });
    updateCount();
}
function applyPermissionVisibility() {
    const allowSpells = professorState.canManageSpells;
    const hideIfNoSpells = (el) => {
        if (!el) return;
        el.style.display = allowSpells ? '' : 'none';
    };
    hideIfNoSpells(professorDOM.addSpellPermanentBtn);
    hideIfNoSpells(professorDOM.addAllPermanentBtn);
    hideIfNoSpells(professorDOM.removeAllPermanentBtn);
    hideIfNoSpells(professorDOM.setMaxLevelBtn);
    hideIfNoSpells(professorDOM.resetCooldownBtn);

    const detailsLevel = document.querySelector('.player-details-level');
    const detailsSpells = document.querySelector('.player-details-spells');
    hideIfNoSpells(detailsLevel);
    hideIfNoSpells(detailsSpells);

    const inlineInfos = document.querySelectorAll('.player-details-info-inline');
    inlineInfos.forEach(el => {
        if (!allowSpells) {
            el.style.display = 'none';
        } else {
            el.style.display = '';
        }
    });

    const courseTab = Array.from(professorDOM.tabs || []).find(tab => tab.dataset.tab === 'course');
    const spellsTab = Array.from(professorDOM.tabs || []).find(tab => tab.dataset.tab === 'spells');
    const pointsTab = Array.from(professorDOM.tabs || []).find(tab => tab.dataset.tab === 'points');
    const coursePanel = document.getElementById('tab-course');
    const spellsPanel = document.getElementById('tab-spells');
    const pointsPanel = document.getElementById('tab-points');

    if (!allowSpells) {
        // Pour le job 'professeur' : cacher Cours et Sorts, afficher uniquement Points
        if (courseTab) courseTab.style.display = 'none';
        if (coursePanel) coursePanel.style.display = 'none';
        if (spellsTab) spellsTab.style.display = 'none';
        if (spellsPanel) spellsPanel.style.display = 'none';
        if (pointsTab) pointsTab.style.display = '';
        if (pointsPanel) pointsPanel.style.display = '';
    } else {
        // Pour le job 'wand_professeur' : afficher les 3 onglets
        if (courseTab) courseTab.style.display = '';
        if (coursePanel) coursePanel.style.display = '';
        if (spellsTab) spellsTab.style.display = '';
        if (spellsPanel) spellsPanel.style.display = '';
        if (pointsTab) pointsTab.style.display = '';
        if (pointsPanel) pointsPanel.style.display = '';
    }
}

function ensureSkillpointButton() {
    if (professorDOM.giveSkillpointBtn) return;
    const container = document.querySelector('.player-details-actions');
    if (!container) return;

    const btn = document.createElement('button');
    btn.className = 'action-btn primary';
    btn.id = 'give-skillpoint-btn';
    btn.textContent = 'Points compétence';

    // place near set-max-level if present
    const before = document.getElementById('set-max-level-btn');
    if (before && before.parentElement === container) {
        container.insertBefore(btn, before);
    } else {
        container.appendChild(btn);
    }

    professorDOM.giveSkillpointBtn = btn;
    btn.addEventListener('click', () => {
        openSkillPointModal();
    });
}

let currentEditingSpell = null;

function showProfessorNotification(type, title, message, duration = 5000) {
    if (!professorDOM.notificationsContainer) return;

    const notification = document.createElement('div');
    notification.className = `professor-notification ${type}`;
    
    notification.innerHTML = `
        <div class="professor-notification-title">${title || 'Notification'}</div>
        <div class="professor-notification-message">${message || ''}</div>
    `;

    professorDOM.notificationsContainer.appendChild(notification);

    setTimeout(() => {
        notification.classList.add('show');
    }, 10);

    setTimeout(() => {
        notification.classList.remove('show');
        notification.classList.add('hide');
        setTimeout(() => {
            if (notification.parentNode) {
                notification.remove();
            }
        }, 300);
    }, duration);
}

function professorNotify(type, title, message, duration) {
    showProfessorNotification(type, title, message, duration);
}

function sanitizePlayerName(player) {
    return player?.name || 'Inconnu';
}

function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
}

function normalizeLevel(level) {
    return clamp(parseInt(level, 10) || 0, 0, MAX_SPELL_LEVEL);
}

function formatLevel(level) {
    const safeLevel = normalizeLevel(level);
    return { value: safeLevel, label: `Niveau ${safeLevel}/${MAX_SPELL_LEVEL}` };
}

function closeModal() {
    if (professorDOM.modalLayer) {
        if (professorDOM.modalLayer._outsideHandler) {
            professorDOM.modalLayer.removeEventListener('click', professorDOM.modalLayer._outsideHandler);
            professorDOM.modalLayer._outsideHandler = null;
        }
        professorDOM.modalLayer.innerHTML = '';
        professorDOM.modalLayer.classList.remove('visible');
    }
}

function openModal(title, body, actions = []) {
    if (!professorDOM.modalLayer) return;
    closeModal();
    professorDOM.modalLayer.classList.add('visible');

    const shell = document.createElement('div');
    shell.className = 'modal-shell';
    shell.innerHTML = `
        <div class="modal-header">
            <div>
                <p class="panel-kicker">Interaction</p>
                <h3>${title}</h3>
            </div>
            <button class="professor-icon-btn" data-close>✕</button>
        </div>
        <div class="modal-body">${body}</div>
        <div class="modal-footer"></div>
    `;

    const footer = shell.querySelector('.modal-footer');
    actions.forEach(action => {
        const btn = document.createElement('button');
        btn.className = `pill-btn ${action.variant || ''}`;
        btn.textContent = action.label;
        btn.addEventListener('click', () => {
            if (typeof action.onClick === 'function') {
                action.onClick();
            }
        });
        footer.appendChild(btn);
    });

    professorDOM.modalLayer.appendChild(shell);

    const closeBtn = shell.querySelector('[data-close]');
    if (closeBtn) {
        closeBtn.addEventListener('click', closeModal);
    }

    if (professorDOM.modalLayer._outsideHandler) {
        professorDOM.modalLayer.removeEventListener('click', professorDOM.modalLayer._outsideHandler);
    }
    professorDOM.modalLayer._outsideHandler = function(event) {
        if (event.target === professorDOM.modalLayer) {
            closeModal();
        }
    };
    professorDOM.modalLayer.addEventListener('click', professorDOM.modalLayer._outsideHandler, { once: true });
}

function openSkillPointModal() {
    if (!professorState.selectedPlayer) {
        professorNotify('error', 'Erreur', 'Aucun élève sélectionné');
        return;
    }

    const body = `
        <p class="helper-text" style="margin-bottom: 12px;">Définis le nombre de points de compétence à donner à <strong>${professorState.selectedPlayer.name}</strong>.</p>
        <input type="number" id="skillpoint-input" class="professor-input" min="1" max="50" value="1" style="width:100%;">
    `;

    openModal('Points de compétence', body, [
        { label: 'Annuler', onClick: closeModal },
        {
            label: 'Envoyer',
            variant: 'primary',
            onClick: () => {
                const input = document.getElementById('skillpoint-input');
                const raw = input ? parseInt(input.value, 10) : 1;
                const amount = Math.max(1, Math.min(50, isNaN(raw) ? 1 : raw));
                const targetId = professorState.selectedPlayer.id;
                postNui('professorGiveSkillPoint', { playerId: targetId, amount });
                professorNotify('success', 'Succès', `+${amount} point(s) de compétence envoyés à ${professorState.selectedPlayer.name}`);
                setTimeout(() => {
                    if (professorState.selectedPlayer && professorState.selectedPlayer.id === targetId) {
                        postNui('professorGetPlayerSpells', { playerId: targetId });
                    }
                }, 400);
                closeModal();
            }
        }
    ]);
}

function showRemoveSkillModal(playerId, playerName, skills, availablePoints) {
    const availableList = Array.isArray(skills) ? skills : [];
    if (availableList.length === 0) {
        professorNotify('error', 'Erreur', 'Compétences introuvables pour ce joueur.');
        return;
    }

    const options = availableList.map(skill => {
        const lvl = typeof skill.level === 'number' ? skill.level : 0;
        return `<option value="${skill.id}" data-level="${lvl}">${skill.label || skill.id} — ${lvl} pts</option>`;
    }).join('');

    const body = `
        <p class="helper-text" style="margin-bottom: 12px;">Sélectionne la compétence à réduire pour <strong>${playerName}</strong>.</p>
        <label class="muted" style="display:block; margin-bottom:6px;">Compétence</label>
        <select id="skill-remove-select" class="professor-input" style="width:100%; margin-bottom:10px;">
            ${options}
        </select>
        <label class="muted" style="display:block; margin-bottom:6px;">Points à retirer (max selon le niveau)</label>
        <input type="number" id="skillpoint-remove-input" class="professor-input" min="1" max="50" value="1" style="width:100%; margin-bottom:8px;">
        ${typeof availablePoints === 'number' ? `<p class="muted">Points disponibles (non attribués) : <strong>${availablePoints}</strong></p>` : ''}
    `;

    openModal('Retirer des points', body, [
        { label: 'Annuler', onClick: closeModal },
        {
            label: 'Retirer',
            variant: 'danger',
            onClick: () => {
                const select = document.getElementById('skill-remove-select');
                const input = document.getElementById('skillpoint-remove-input');
                const raw = input ? parseInt(input.value, 10) : 1;
                const amount = Math.max(1, Math.min(50, isNaN(raw) ? 1 : raw));
                const skillId = select ? select.value : null;
                const level = select ? parseInt(select.selectedOptions[0]?.dataset.level || '0', 10) : 0;
                const clamped = Math.min(amount, Math.max(0, level));

                if (!skillId) {
                    professorNotify('error', 'Erreur', 'Choisis une compétence.');
                    return;
                }

                postNui('professorRemoveSkillLevel', { playerId, skillId, amount: clamped });
                professorNotify('success', 'Succès', `-${clamped} point(s) retirés sur ${skillId} pour ${playerName}`);
                setTimeout(() => postNui('professorGetPlayerSpells', { playerId }), 400);
                closeModal();
            }
        }
    ]);
}

function openProfessorMenu(data) {
    professorState.visible = true;
    professorState.canManageSpells = data?.canManageSpells !== false;
    if (professorDOM.menu) {
        professorDOM.menu.classList.add('active');
        professorDOM.menu.dataset.canManageSpells = professorState.canManageSpells ? 'true' : 'false';
    }
    document.body.classList.add('professor-open');

    if (data?.spells) {
        professorState.allSpells = data.spells || [];
        professorState.allSpellsRef = professorState.allSpells;
    }
    if (data?.players) {
        professorState.allPlayers = data.players || [];
        professorState.allPlayersRef = professorState.allPlayers;
    }
    if (data?.professor) {
        professorState.professor = data.professor;
    }
    if (professorDOM.playerSkillpoints) {
        professorDOM.playerSkillpoints.textContent = 'Points compétence : --';
    }

    loadProfessorData();
    switchTab(professorState.currentTab);
    applyPermissionVisibility();
}

function closeProfessorMenu() {
    professorState.visible = false;
    if (professorDOM.menu) {
        professorDOM.menu.classList.remove('active');
    }
    document.body.classList.remove('professor-open');
    professorState.selectedPlayer = null;
    professorState.selectedPlayerSpells = {};
    currentEditingSpell = null;
    if (professorDOM.playerSkillpoints) {
        professorDOM.playerSkillpoints.textContent = 'Points compétence : --';
    }
    closeModal();
    postNui('closeProfessorMenu', {});
}

function switchTab(tabName) {
    if (!professorState.canManageSpells && tabName === 'course') {
        tabName = 'points';
    }
    professorState.currentTab = tabName;

    professorDOM.tabs.forEach(tab => tab.classList.toggle('active', tab.dataset.tab === tabName));
    professorDOM.tabContents.forEach(content => content.classList.toggle('active', content.id === `tab-${tabName}`));

    if (tabName === 'course') {
        refreshNearbyPlayers();
        renderTempSpells();
    } else if (tabName === 'spells') {
        refreshNearbyPlayers();
        if (professorState.canManageSpells) {
            renderAllSpells();
        }
        renderAllPlayers();
    } else if (tabName === 'points') {
        refreshNearbyPlayers();
        renderBulkPoints();
    }
}

function loadProfessorData() {
    postNui('professorGetData', {});
}

function refreshNearbyPlayers() {
    postNui('professorGetNearbyPlayers', { radius: 10.0 });
}

function renderNearbyStudents(players) {
    if (!professorDOM.nearbyStudentsList) return;
    professorState.nearbyPlayers = players || [];

    if (!professorState.canManageSpells) {
        professorDOM.nearbyStudentsList.innerHTML = '<div class="empty-state">Gestion des sorts temporaires non disponible pour ce rôle.</div>';
        renderBulkPoints();
        return;
    }

    const roster = [...professorState.nearbyPlayers];

    if (professorState.professor) {
        const alreadyListed = roster.some(player => player.id === professorState.professor.id);
        if (!alreadyListed) {
            roster.unshift({
                ...professorState.professor,
                distance: 0,
                isProfessor: true
            });
        }
    }

    if (roster.length === 0) {
        professorDOM.nearbyStudentsList.innerHTML = '<div class="empty-state">Aucun élève à proximité (10m)</div>';
        return;
    }

    professorDOM.nearbyStudentsList.innerHTML = roster.map(player => `
        <details class="accordion">
            <summary>
                <div class="accordion-title">
                    <span class="tag ${player.isProfessor ? 'accent' : ''}">${player.isProfessor ? 'Professeur' : 'Élève'}</span>
                    <div class="accordion-meta">
                        <span class="title">${sanitizePlayerName(player)}</span>
                        <span class="muted">ID ${player.id}</span>
                        <span class="muted">${player.distance ? `${player.distance.toFixed(1)} m` : 'à portée'}</span>
                    </div>
                </div>
            </summary>
            <div class="accordion-body">
                <div class="chip-row">
                    <button class="pill-btn primary" data-player="${player.id}" data-player-name="${sanitizePlayerName(player)}" data-action="assign-spell" data-tooltip="Attribuer un sort temporaire (pour la durée du cours uniquement)">Attribuer temporaire</button>
                </div>
            </div>
        </details>
    `).join('');

    professorDOM.nearbyStudentsList.querySelectorAll('[data-action="assign-spell"]').forEach(btn => {
        btn.addEventListener('click', () => {
            const id = parseInt(btn.dataset.player, 10);
            const name = btn.dataset.playerName;
            giveSpellToStudent(id, name);
        });
    });
}

function openSpellSelectionModal(playerId, playerName, availableSpells) {
    const list = availableSpells.map(spell => `
        <button class="list-row spell-search-item" data-spell="${spell.id}" data-spell-name="${(spell.name || spell.id).toLowerCase()}" data-spell-desc="${(spell.description || '').toLowerCase()}">
            <div class="list-main">
                <strong>${spell.name || spell.id}</strong>
                <span class="muted">${spell.description || 'Aucune description'}</span>
            </div>
            <span class="pill">${spell.type || 'Divers'}</span>
        </button>
    `).join('');

    openModal(`Attribuer un sort temporaire à ${playerName}`, `
        <p class="helper-text" style="margin-bottom: 16px;">Les sorts temporaires sont uniquement pour la durée du cours et ne sont pas inscrits dans le grimoire.</p>
        <input type="text" class="professor-input modal-search-input" id="modal-spell-search" placeholder="Rechercher un sort..." style="width: 100%; max-width: 100%; margin-bottom: 12px;">
        <div class="stack small-scroll" id="modal-spell-list">${list || '<div class="empty-state">Aucun sort disponible</div>'}</div>
    `, [
        { label: 'Fermer', onClick: closeModal }
    ]);

    setTimeout(() => {
        const searchInput = document.getElementById('modal-spell-search');
        const spellItems = professorDOM.modalLayer?.querySelectorAll('.spell-search-item');
        
        if (searchInput && spellItems) {
            searchInput.addEventListener('input', (e) => {
                const searchTerm = e.target.value.toLowerCase().trim();
                
                spellItems.forEach(item => {
                    const spellName = item.dataset.spellName || '';
                    const spellDesc = item.dataset.spellDesc || '';
                    
                    if (spellName.includes(searchTerm) || spellDesc.includes(searchTerm)) {
                        item.style.display = '';
                    } else {
                        item.style.display = 'none';
                    }
                });
            });
        }
        
        professorDOM.modalLayer?.querySelectorAll('[data-spell]').forEach(btn => {
            btn.addEventListener('click', () => {
                const spellId = btn.dataset.spell;
                closeModal();
                setTimeout(() => {
                    selectSpellForStudent(spellId, playerId, playerName);
                }, 50);
            });
        });
    }, 10);
}

function selectSpellForStudent(spellId, playerId, playerName) {
    if (professorState.tempSpells.get(playerId)?.has(spellId)) {
        professorNotify('warning', 'Attention', 'Ce sort est déjà attribué temporairement à cet élève');
        return;
    }

    const spell = professorState.allSpells.find(s => s.id === spellId);
    const spellName = spell ? spell.name : spellId;
    
    const modalBody = `
        <div class="spell-level-control" style="display: block; margin: 0;">
            <div class="form-field">
                <label>Niveau (0-${MAX_SPELL_LEVEL})</label>
                <div class="level-control">
                    <input type="range" id="modal-temp-level" class="professor-slider" min="0" max="${MAX_SPELL_LEVEL}" value="0">
                    <span id="temp-level-value" style="min-width: 40px; text-align: center; font-weight: 700; color: var(--accent);">0</span>
                </div>
            </div>
        </div>
    `;
    
    openModal(`Attribuer ${spellName} (temporaire)`, modalBody, [
        { label: 'Attribuer', variant: 'primary', onClick: () => {
            const currentModalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
            let levelInput;
            
            if (currentModalShell) {
                levelInput = currentModalShell.querySelector('#modal-temp-level');
            }
            
            if (!levelInput) levelInput = document.getElementById('modal-temp-level');
            
            const levelValue = levelInput ? normalizeLevel(levelInput.value) : 0;
            
            const actionKey = `${playerId}_${spellId}`;
            professorState.pendingSpellActions.set(actionKey, { playerId, spellId, playerName, level: levelValue });

            postNui('professorGiveTempSpell', { playerId, spellId, level: levelValue });
            closeModal();
        }},
        { label: 'Annuler', onClick: closeModal }
    ]);

    requestAnimationFrame(() => {
        let modalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
        if (!modalShell) {
            setTimeout(() => {
                modalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
                if (!modalShell) return;
                initializeLevelControls(modalShell);
            }, 50);
            return;
        }
        initializeLevelControls(modalShell);
    });
    
    function initializeLevelControls(modalShell) {
        const levelSlider = modalShell.querySelector('#modal-temp-level');
        const levelDisplay = modalShell.querySelector('#temp-level-value');

        if (!levelSlider || !levelDisplay) {
            return;
        }

        const refreshDisplay = () => {
            const lvl = normalizeLevel(levelSlider.value);
            levelSlider.value = lvl;
            levelDisplay.textContent = lvl;
        };

        levelSlider.addEventListener('input', refreshDisplay);
        refreshDisplay();
    }
}

function selectSpellForStudentPermanent(spellId, playerId, playerName) {
    if (professorState.selectedPlayerSpells[spellId]) {
        professorNotify('warning', 'Attention', 'Cet élève possède déjà ce sort');
        return;
    }

    const spell = professorState.allSpells.find(s => s.id === spellId);
    const spellName = spell ? spell.name : spellId;

    const modalBody = `
        <div class="spell-level-control" style="display: block; margin: 0;">
            <div class="form-field">
                <label>Niveau (0-${MAX_SPELL_LEVEL})</label>
                <div class="level-control">
                    <input type="range" id="modal-perm-level" class="professor-slider" min="0" max="${MAX_SPELL_LEVEL}" value="0">
                    <span id="perm-level-value" style="min-width: 40px; text-align: center; font-weight: 700; color: var(--accent);">0</span>
                </div>
            </div>
            <div class="level-info">
                <p>Niveau sélectionné: <span id="perm-total-value" style="font-weight: 700; color: var(--accent); font-size: 16px;">0</span> / ${MAX_SPELL_LEVEL}</p>
            </div>
            <p class="helper-text">Les niveaux vont de 0 (débutant) à ${MAX_SPELL_LEVEL} (maîtrise complète).</p>
        </div>
    `;

    openModal(`Attribuer ${spellName} (définitif)`, modalBody, [
        { label: 'Attribuer', variant: 'primary', onClick: () => {
            const currentModalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
            let levelInput;

            if (currentModalShell) {
                levelInput = currentModalShell.querySelector('#modal-perm-level');
            }

            if (!levelInput) levelInput = document.getElementById('modal-perm-level');

            const levelValue = levelInput ? normalizeLevel(levelInput.value) : 0;

            postNui('professorGiveSpell', { playerId, spellId, level: levelValue });
            setTimeout(() => {
                postNui('professorGetPlayerSpells', { playerId });
            }, 500);
            closeModal();
        }},
        { label: 'Annuler', onClick: closeModal }
    ]);

    requestAnimationFrame(() => {
        let modalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
        if (!modalShell) {
            setTimeout(() => {
                modalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
                if (!modalShell) return;
                initializePermanentLevelControls(modalShell);
            }, 50);
            return;
        }
        initializePermanentLevelControls(modalShell);
    });

    function initializePermanentLevelControls(modalShell) {
        const levelSlider = modalShell.querySelector('#modal-perm-level');
        const levelDisplay = modalShell.querySelector('#perm-level-value');
        const totalDisplay = modalShell.querySelector('#perm-total-value');

        if (!levelSlider || !levelDisplay) {
            return;
        }

        const refreshDisplay = () => {
            const lvl = normalizeLevel(levelSlider.value);
            levelSlider.value = lvl;
            levelDisplay.textContent = lvl;
            if (totalDisplay) totalDisplay.textContent = lvl;
        };

        levelSlider.addEventListener('input', refreshDisplay);
        refreshDisplay();
    }
}

function selectSpellForMultiplePlayers(spellId, playerIds) {
    const spell = professorState.allSpells.find(s => s.id === spellId);
    const spellName = spell ? spell.name : spellId;
    const playerCount = playerIds.length;

    const modalBody = `
        <div class="spell-level-control" style="display: block; margin: 0;">
            <div class="form-field">
                <label>Niveau (0-${MAX_SPELL_LEVEL})</label>
                <div class="level-control">
                    <input type="range" id="modal-multi-level" class="professor-slider" min="0" max="${MAX_SPELL_LEVEL}" value="0">
                    <span id="multi-level-value" style="min-width: 40px; text-align: center; font-weight: 700; color: var(--accent);">0</span>
                </div>
            </div>
            <div class="level-info">
                <p>Niveau sélectionné: <span id="multi-total-value" style="font-weight: 700; color: var(--accent); font-size: 16px;">0</span> / ${MAX_SPELL_LEVEL}</p>
            </div>
            <p class="helper-text">Les niveaux vont de 0 (débutant) à ${MAX_SPELL_LEVEL} (maîtrise complète).</p>
            <p class="helper-text" style="margin-top: 8px; color: var(--accent);">${playerCount} élève(s) recevront ce sort.</p>
        </div>
    `;

    openModal(`Attribuer ${spellName} à tous`, modalBody, [
        { label: 'Attribuer', variant: 'primary', onClick: () => {
            const currentModalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
            let levelInput;

            if (currentModalShell) {
                levelInput = currentModalShell.querySelector('#modal-multi-level');
            }

            if (!levelInput) levelInput = document.getElementById('modal-multi-level');

            const levelValue = levelInput ? normalizeLevel(levelInput.value) : 0;

            postNui('professorGiveSpellToMultiple', { playerIds, spellId, level: levelValue });
            professorNotify('info', 'En cours', `Attribution de "${spellName}" à ${playerCount} élève(s)...`);
            closeModal();
        }},
        { label: 'Annuler', onClick: closeModal }
    ]);

    requestAnimationFrame(() => {
        let modalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
        if (!modalShell) {
            setTimeout(() => {
                modalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
                if (!modalShell) return;
                initializeMultiLevelControls(modalShell);
            }, 50);
            return;
        }
        initializeMultiLevelControls(modalShell);
    });

    function initializeMultiLevelControls(modalShell) {
        const levelSlider = modalShell.querySelector('#modal-multi-level');
        const levelDisplay = modalShell.querySelector('#multi-level-value');
        const totalDisplay = modalShell.querySelector('#multi-total-value');

        if (!levelSlider || !levelDisplay) {
            return;
        }

        const refreshDisplay = () => {
            const lvl = normalizeLevel(levelSlider.value);
            levelSlider.value = lvl;
            levelDisplay.textContent = lvl;
            if (totalDisplay) totalDisplay.textContent = lvl;
        };

        levelSlider.addEventListener('input', refreshDisplay);
        refreshDisplay();
    }
}

function giveSpellToStudent(playerId, playerName) {
    if (professorState.allSpells.length === 0) {
        professorNotify('error', 'Erreur', 'Aucun sort disponible');
        return;
    }

    const availableSpells = professorState.allSpells.filter(spell => 
        !professorState.tempSpells.get(playerId)?.has(spell.id)
    );

    if (availableSpells.length === 0) {
        professorNotify('error', 'Erreur', 'Tous les sorts ont déjà été attribués à cet élève');
        return;
    }

    openSpellSelectionModal(playerId, playerName, availableSpells);
}

function giveSpellToAllNearby(spellId) {
    if (professorState.nearbyPlayers.length === 0) {
        professorNotify('error', 'Erreur', 'Aucun élève à proximité');
        return;
    }

    const eligiblePlayers = professorState.nearbyPlayers.filter(player =>
        !professorState.tempSpells.get(player.id)?.has(spellId)
    );

    if (eligiblePlayers.length === 0) {
        professorNotify('warning', 'Attention', 'Tous les élèves à proximité ont déjà ce sort temporairement');
        return;
    }

    selectTempSpellForMultiplePlayers(spellId, eligiblePlayers);
}

function selectTempSpellForMultiplePlayers(spellId, players) {
    const spell = professorState.allSpells.find(s => s.id === spellId);
    const spellName = spell ? spell.name : spellId;
    const playerCount = players.length;

    const modalBody = `
        <div class="spell-level-control" style="display: block; margin: 0;">
            <div class="form-field">
                <label>Niveau (0-${MAX_SPELL_LEVEL})</label>
                <div class="level-control">
                    <input type="range" id="modal-temp-multi-level" class="professor-slider" min="0" max="${MAX_SPELL_LEVEL}" value="0">
                    <span id="temp-multi-level-value" style="min-width: 40px; text-align: center; font-weight: 700; color: var(--accent);">0</span>
                </div>
            </div>
            <div class="level-info">
                <p>Niveau sélectionné: <span id="temp-multi-total-value" style="font-weight: 700; color: var(--accent); font-size: 16px;">0</span> / ${MAX_SPELL_LEVEL}</p>
            </div>
            <p class="helper-text">Les niveaux vont de 0 (débutant) à ${MAX_SPELL_LEVEL} (maîtrise complète).</p>
            <p class="helper-text" style="margin-top: 8px; color: var(--accent);">${playerCount} élève(s) recevront ce sort temporairement.</p>
        </div>
    `;

    openModal(`Attribuer ${spellName} (temporaire) à tous`, modalBody, [
        { label: 'Attribuer', variant: 'primary', onClick: () => {
            const currentModalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
            let levelInput;

            if (currentModalShell) {
                levelInput = currentModalShell.querySelector('#modal-temp-multi-level');
            }

            if (!levelInput) levelInput = document.getElementById('modal-temp-multi-level');

            const levelValue = levelInput ? normalizeLevel(levelInput.value) : 0;

            players.forEach(player => {
                postNui('professorGiveTempSpell', { playerId: player.id, spellId, level: levelValue });
            });

            renderTempSpells();
            professorNotify('info', 'En cours', `Attribution de "${spellName}" (temporaire) à ${playerCount} élève(s)...`);
            closeModal();
        }},
        { label: 'Annuler', onClick: closeModal }
    ]);

    requestAnimationFrame(() => {
        let modalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
        if (!modalShell) {
            setTimeout(() => {
                modalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
                if (!modalShell) return;
                initializeTempMultiLevelControls(modalShell);
            }, 50);
            return;
        }
        initializeTempMultiLevelControls(modalShell);
    });

    function initializeTempMultiLevelControls(modalShell) {
        const levelSlider = modalShell.querySelector('#modal-temp-multi-level');
        const levelDisplay = modalShell.querySelector('#temp-multi-level-value');
        const totalDisplay = modalShell.querySelector('#temp-multi-total-value');

        if (!levelSlider || !levelDisplay) {
            return;
        }

        const refreshDisplay = () => {
            const lvl = normalizeLevel(levelSlider.value);
            levelSlider.value = lvl;
            levelDisplay.textContent = lvl;
            if (totalDisplay) totalDisplay.textContent = lvl;
        };

        levelSlider.addEventListener('input', refreshDisplay);
        refreshDisplay();
    }
}

function giveDefSpellToAllNearby(spellId) {
    if (professorState.nearbyPlayers.length === 0) {
        professorNotify('error', 'Erreur', 'Aucun élève à proximité');
        return;
    }

    const playerIds = professorState.nearbyPlayers.map(p => p.id);
    selectSpellForMultiplePlayers(spellId, playerIds);
}


function showConfirmModal(message, callback) {
    openModal('Confirmer', `<p>${message}</p>`, [
        { label: 'Confirmer', variant: 'primary', onClick: () => { callback(); closeModal(); } },
        { label: 'Annuler', onClick: closeModal }
    ]);
}

function removeAllTempSpells() {
    if (professorState.tempSpells.size === 0) {
        professorNotify('info', 'Information', 'Aucun sort temporaire à retirer');
        return;
    }

    professorState.tempSpells.forEach((spellSet, playerId) => {
        spellSet.forEach((level, spellId) => {
            postNui('professorRemoveTempSpell', { playerId, spellId });
        });
    });

    professorState.tempSpells.clear();
    renderTempSpells();
    refreshNearbyPlayers();

    addToHistory('Retrait tous sorts temporaires', 'Tous les élèves', '');
    professorNotify('success', 'Succès', 'Tous les sorts temporaires ont été retirés.');
}

function renderTempSpells() {
    if (!professorDOM.tempSpellsList) return;

    if (professorState.tempSpells.size === 0) {
        professorDOM.tempSpellsList.innerHTML = '<div class="empty-state">Aucun sort temporaire attribué</div>';
        return;
    }

    const items = [];
    professorState.tempSpells.forEach((spellMap, playerId) => {
        const player = professorState.allPlayers.find(p => p.id === playerId) || 
                      professorState.nearbyPlayers.find(p => p.id === playerId);
        const playerName = player ? player.name : `Joueur ${playerId}`;

        spellMap.forEach((level, spellId) => {
            const spell = professorState.allSpells.find(s => s.id === spellId);
        const spellName = spell ? spell.name : spellId;
            const normalized = normalizeLevel(level);
            items.push({ playerId, playerName, spellId, spellName, level: normalized });
        });
    });

    professorDOM.tempSpellsList.innerHTML = items.map(item => {
        const levelText = `Niveau ${item.level}/${MAX_SPELL_LEVEL}`;
        return `
        <details class="accordion">
            <summary>
                <div class="accordion-title">
                    <span class="title">${item.spellName}</span>
                    <span class="muted">${item.playerName} • ID ${item.playerId}</span>
                </div>
            </summary>
            <div class="accordion-body">
                <div style="margin-bottom: 12px;">
                    <p class="muted" style="font-size: 13px; margin-bottom: 8px;">Niveau actuel:</p>
                    <p style="font-weight: 600; color: var(--accent);">${levelText}</p>
                </div>
                <div class="chip-row">
                    <button class="pill-btn" data-action="edit-temp-level" data-player-id="${item.playerId}" data-spell-id="${item.spellId}" data-current-level="${item.level}">Modifier niveau</button>
                    <button class="pill-btn danger" data-action="remove-temp" data-player-id="${item.playerId}" data-spell-id="${item.spellId}">Retirer</button>
                </div>
            </div>
        </details>
    `;
    }).join('');

    professorDOM.tempSpellsList.querySelectorAll('[data-action="remove-temp"]').forEach(btn => {
        btn.addEventListener('click', () => {
            const playerId = parseInt(btn.dataset.playerId, 10);
            const spellId = btn.dataset.spellId;
            removeTempSpell(playerId, spellId);
        });
    });

    professorDOM.tempSpellsList.querySelectorAll('[data-action="edit-temp-level"]').forEach(btn => {
        btn.addEventListener('click', () => {
            const playerId = parseInt(btn.dataset.playerId, 10);
            const spellId = btn.dataset.spellId;
            const currentLevel = parseInt(btn.dataset.currentLevel, 10) || 0;
            const player = professorState.allPlayers.find(p => p.id === playerId) || 
                          professorState.nearbyPlayers.find(p => p.id === playerId);
            const playerName = player ? player.name : `Joueur ${playerId}`;
            editTempSpellLevel(spellId, playerId, playerName, currentLevel);
        });
    });
}

function removeTempSpell(playerId, spellId) {
    postNui('professorRemoveTempSpell', { playerId, spellId });

    if (professorState.tempSpells.has(playerId)) {
        professorState.tempSpells.get(playerId).delete(spellId);
        if (professorState.tempSpells.get(playerId).size === 0) {
            professorState.tempSpells.delete(playerId);
        }
    }

    renderTempSpells();
}

function editTempSpellLevel(spellId, playerId, playerName, currentLevel) {
    const spell = professorState.allSpells.find(s => s.id === spellId);
    const spellName = spell ? spell.name : spellId;
    const safeLevel = normalizeLevel(currentLevel);
    
    const modalBody = `
        <div class="spell-level-control" style="display: block; margin: 0;">
            <div class="form-field">
                <label>Niveau (0-${MAX_SPELL_LEVEL})</label>
                <div class="level-control">
                    <input type="range" id="modal-edit-temp-level" class="professor-slider" min="0" max="${MAX_SPELL_LEVEL}" value="${safeLevel}">
                    <span id="edit-temp-level-value" style="min-width: 40px; text-align: center; font-weight: 700; color: var(--accent);">${safeLevel}</span>
                </div>
            </div>
        </div>
    `;
    
    openModal(`Modifier le niveau de ${spellName} (temporaire)`, modalBody, [
        { label: 'Mettre à jour', variant: 'primary', onClick: () => {
            const currentModalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
            let levelInput;
            
            if (currentModalShell) {
                levelInput = currentModalShell.querySelector('#modal-edit-temp-level');
            }
            
            if (!levelInput) levelInput = document.getElementById('modal-edit-temp-level');
            
            const levelValue = levelInput ? normalizeLevel(levelInput.value) : 0;
            
            const actionKey = `${playerId}_${spellId}`;
            professorState.pendingSpellActions.set(actionKey, { playerId, spellId, level: levelValue });
            
            postNui('professorUpdateTempSpellLevel', { playerId, spellId, level: levelValue });
            closeModal();
        }},
        { label: 'Annuler', onClick: closeModal }
    ]);

    requestAnimationFrame(() => {
        const modalShell = professorDOM.modalLayer?.querySelector('.modal-shell');
        if (!modalShell) {
            setTimeout(() => {
                const retryShell = professorDOM.modalLayer?.querySelector('.modal-shell');
                if (!retryShell) return;
                initializeEditLevelControls(retryShell);
            }, 50);
            return;
        }
        initializeEditLevelControls(modalShell);
    });
    
    function initializeEditLevelControls(shell) {
        const levelSlider = shell.querySelector('#modal-edit-temp-level');
        const levelDisplay = shell.querySelector('#edit-temp-level-value');

        if (!levelSlider || !levelDisplay) {
            return;
        }

        const refreshDisplay = () => {
            const lvl = normalizeLevel(levelSlider.value);
            levelSlider.value = lvl;
            levelDisplay.textContent = lvl;
        };

        levelSlider.addEventListener('input', refreshDisplay);
        refreshDisplay();
    }
}

function renderAllSpells() {
    if (!professorState.canManageSpells) {
        if (professorDOM.allSpellsGrid) {
            professorDOM.allSpellsGrid.innerHTML = '<div class="empty-state">Gestion des sorts non disponible pour ce rôle.</div>';
        }
        return;
    }

    if (!professorDOM.allSpellsGrid) return;
    
    if (professorState.allSpells.length === 0) {
        professorDOM.allSpellsGrid.innerHTML = '<div class="empty-state">Aucun sort disponible</div>';
        return;
    }
    
    let filteredSpells = professorState.allSpells;
    const searchTerm = (professorDOM.spellSearch && professorDOM.spellSearch.value) ? professorDOM.spellSearch.value.toLowerCase() : '';

    if (professorState._lastSpellRender &&
        professorState._lastSpellRender.ref === professorState.allSpellsRef &&
        professorState._lastSpellRender.term === searchTerm) {
        return;
    }

    if (searchTerm) {
        filteredSpells = filteredSpells.filter(spell => 
            (spell.name || '').toLowerCase().includes(searchTerm) ||
            (spell.id || '').toLowerCase().includes(searchTerm) ||
            (spell.description || '').toLowerCase().includes(searchTerm)
        );
    }

    if (filteredSpells.length === 0) {
        professorDOM.allSpellsGrid.innerHTML = '<div class="empty-state">Aucun sort trouvé</div>';
        return;
    }

    const grouped = filteredSpells.reduce((acc, spell) => {
        const key = (spell.type || 'Divers').toUpperCase();
        if (!acc[key]) acc[key] = [];
        acc[key].push(spell);
        return acc;
    }, {});

    professorDOM.allSpellsGrid.innerHTML = Object.entries(grouped).map(([category, spells]) => `
        <details class="accordion">
            <summary>
                <div class="accordion-title">
                    <span class="tag">${category}</span>
                    <span class="muted">${spells.length} sort(s)</span>
                </div>
            </summary>
            <div class="accordion-body stack">
                ${spells.map(spell => {
                    const iconPath = spell.icon || spell.image || '';
                    const iconUrl = iconPath ? `nui://dvr_power/html/${iconPath}` : '';
                    return `
                        <div class="card-row spell-card-row">
                            <div class="card-main">
                                ${iconUrl ? `<img src="${iconUrl}" alt="${spell.name || spell.id}" class="spell-icon">` : ''}
                                <div>
                                    <div class="title">${spell.name || spell.id}</div>
                                    <div class="muted">${spell.description || 'Aucune description'}</div>
                                </div>
                            </div>
                            <div class="chip-row">
                                <button class="pill-btn primary" data-action="assign-all-def" data-spell-id="${spell.id}" data-tooltip="Donner ce sort définitivement à tous les élèves à proximité">Donner à tous (Déf.)</button>
                                <button class="pill-btn" data-action="assign-all" data-spell-id="${spell.id}" data-tooltip="Donner ce sort temporairement à tous les élèves à proximité">Donner à tous (Temp.)</button>
                            </div>
                        </div>
                    `;
                }).join('')}
            </div>
        </details>
    `).join('');

    if (professorState.canManageSpells) {
        professorDOM.allSpellsGrid.querySelectorAll('[data-action="assign-all"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const spellId = btn.dataset.spellId;
                selectSpellForAll(spellId);
            });
        });
        
        professorDOM.allSpellsGrid.querySelectorAll('[data-action="assign-all-def"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const spellId = btn.dataset.spellId;
                giveDefSpellToAllNearby(spellId);
            });
        });
    }
}

function selectSpellForAll(spellId) {
    if (professorState.nearbyPlayers.length === 0) {
        professorNotify('info', 'Information', 'Aucun élève à proximité. Ouvrez l\'onglet "Cours" pour voir les élèves proches.');
        return;
    }

    const spell = professorState.allSpells.find(s => s.id === spellId);
    const spellName = spell ? spell.name : spellId;

    giveSpellToAllNearby(spellId);
    professorNotify('success', 'Succès', `Sort "${spellName}" attribué temporairement à ${professorState.nearbyPlayers.length} élève(s).`);
}

function renderAllPlayers() {
    if (!professorDOM.playersList) return;

    if (professorState.allPlayers.length === 0) {
        professorDOM.playersList.innerHTML = '<div class="empty-state">Aucun joueur connecté</div>';
        return;
    }

    let filteredPlayers = professorState.allPlayers;
    const searchTerm = (professorDOM.playerSearch && professorDOM.playerSearch.value) ? professorDOM.playerSearch.value.toLowerCase() : '';
    const selectedId = professorState.selectedPlayer?.id || null;
    const expandedKey = Array.from(professorState.expandedPlayers || []).join(',');

    if (professorState._lastPlayerRender &&
        professorState._lastPlayerRender.ref === professorState.allPlayersRef &&
        professorState._lastPlayerRender.term === searchTerm &&
        professorState._lastPlayerRender.selectedId === selectedId &&
        professorState._lastPlayerRender.expandedKey === expandedKey) {
        return;
    }

    if (searchTerm) {
        filteredPlayers = filteredPlayers.filter(player => 
            (player.name || '').toLowerCase().includes(searchTerm) ||
            (player.id || '').toString().includes(searchTerm)
        );
    }

    const selectedPlayerId = professorState.selectedPlayer?.id;

    professorDOM.playersList.innerHTML = filteredPlayers.map(player => {
        const isExpanded = professorState.expandedPlayers.has(player.id);
        const isSelected = selectedPlayerId === player.id;
        const canSpells = professorState.canManageSpells;
        
        return `
            <div class="player-card-wrapper" data-player-id="${player.id}">
                <div class="player-card ${isSelected ? 'selected' : ''}" data-player-id="${player.id}">
                    <div class="player-card-info">
                        <span class="player-card-name">${sanitizePlayerName(player)}</span>
                        <span class="player-card-id">ID ${player.id}</span>
                    </div>
                    <button class="pill-btn primary compact" data-action="select-player" data-player-id="${player.id}">${isExpanded ? 'Fermer' : 'Gérer'}</button>
                </div>
                <div class="player-details-inline ${isExpanded ? 'expanded' : ''}" id="player-details-${player.id}">
                    <div class="player-details-header-inline">
                        <div class="player-details-title-inline">
                            <span class="player-details-kicker">Gestion du joueur</span>
                            <h3>${sanitizePlayerName(player)}</h3>
                        </div>
                        <button class="player-details-close" data-action="close-player" data-player-id="${player.id}">✕</button>
                    </div>
                    <div class="player-details-actions-inline">
                        ${canSpells ? `<button class="action-btn primary" data-action="add-spell" data-player-id="${player.id}">+ Attribuer</button>` : ''}
                        <button class="action-btn primary" data-action="give-skillpoint-inline" data-player-id="${player.id}">Points compétence</button>
                        <button class="action-btn danger" data-action="remove-skillpoint-inline" data-player-id="${player.id}">Retirer points</button>
                        ${canSpells ? `<button class="action-btn" data-action="reset-cd" data-player-id="${player.id}">Reset CD</button>` : ''}
                    </div>
                    ${canSpells ? `
                    <div class="player-details-level-inline">
                        <span class="level-label">Niveau global :</span>
                        <input type="number" min="0" max="5" value="0" class="level-input" data-level-input="${player.id}">
                        <button class="action-btn primary" data-action="apply-level" data-player-id="${player.id}">Appliquer</button>
                    </div>` : ''}
                    <div class="player-details-info-inline">
                        ✓ Les sorts attribués ici sont <strong>permanents</strong> et inscrits dans le grimoire.
                    </div>
                    ${canSpells ? `<div class="player-details-spells-inline">
                        <div class="spells-list-header" style="display: flex; align-items: center; gap: 8px;">
                            <span>Sorts possédés</span>
                            <input type="text" class="professor-input player-spell-search" data-player-id="${player.id}" placeholder="Rechercher un sort..." style="max-width: 240px; margin-left: auto;">
                        </div>
                        <div class="accordion-list small-scroll player-spells-list-inline" id="player-spells-${player.id}">
                            <div class="empty-state">Aucun sort possédé</div>
                        </div>
                    </div>` : ''}
                </div>
            </div>
        `;
    }).join('');

    if (professorDOM.playerDetailsSection) {
        professorDOM.playerDetailsSection.dataset.visible = 'false';
        professorDOM.playerDetailsSection.style.display = 'none';
    }

    attachPlayerListEvents();

    professorState._lastPlayerRender = {
        ref: professorState.allPlayersRef,
        term: searchTerm,
        selectedId,
        expandedKey
    };
}

function attachPlayerListEvents() {
    professorDOM.playersList.querySelectorAll('[data-action="select-player"]').forEach(btn => {
        btn.addEventListener('click', () => {
            const playerId = parseInt(btn.dataset.playerId, 10);
            const player = professorState.allPlayers.find(p => p.id === playerId);
            selectPlayer(playerId, sanitizePlayerName(player));
        });
    });

    professorDOM.playersList.querySelectorAll('[data-action="close-player"]').forEach(btn => {
        btn.addEventListener('click', () => {
            const playerId = parseInt(btn.dataset.playerId, 10);
            closePlayerDetails(playerId);
        });
    });

    if (professorState.canManageSpells) {
        professorDOM.playersList.querySelectorAll('[data-action="add-spell"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const playerId = parseInt(btn.dataset.playerId, 10);
                const player = professorState.allPlayers.find(p => p.id === playerId);
                if (player) {
                    openSpellSelectionModalForPlayer(playerId, sanitizePlayerName(player), false);
                }
            });
        });
    }

    if (professorState.canManageSpells) {
        professorDOM.playersList.querySelectorAll('[data-action="add-all"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const playerId = parseInt(btn.dataset.playerId, 10);
                postNui('professorGiveAllSpells', { playerId });
                setTimeout(() => postNui('professorGetPlayerSpells', { playerId }), 500);
            });
        });
    }

    if (professorState.canManageSpells) {
        professorDOM.playersList.querySelectorAll('[data-action="remove-all"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const playerId = parseInt(btn.dataset.playerId, 10);
                postNui('professorRemoveAllSpells', { playerId });
                setTimeout(() => postNui('professorGetPlayerSpells', { playerId }), 500);
            });
        });
    }

    if (professorState.canManageSpells) {
        professorDOM.playersList.querySelectorAll('[data-action="reset-cd"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const playerId = parseInt(btn.dataset.playerId, 10);
                postNui('professorResetCooldowns', { playerId });
                professorNotify('success', 'Succès', 'Cooldowns réinitialisés.');
            });
        });
    }

    professorDOM.playersList.querySelectorAll('[data-action="give-skillpoint-inline"]').forEach(btn => {
        btn.addEventListener('click', () => {
            const playerId = parseInt(btn.dataset.playerId, 10);
            const playerName = professorState.allPlayers.find(p => p.id === playerId)?.name || `ID ${playerId}`;

            const body = `
                <p class="helper-text" style="margin-bottom: 12px;">Définis le nombre de points de compétence à donner à <strong>${playerName}</strong>.</p>
                <input type="number" id="skillpoint-input-inline" class="professor-input" min="1" max="50" value="1" style="width:100%;">
            `;

            openModal('Points de compétence', body, [
                { label: 'Annuler', onClick: closeModal },
                {
                    label: 'Envoyer',
                    variant: 'primary',
                    onClick: () => {
                        const input = document.getElementById('skillpoint-input-inline');
                        const raw = input ? parseInt(input.value, 10) : 1;
                        const amount = Math.max(1, Math.min(50, isNaN(raw) ? 1 : raw));
                        postNui('professorGiveSkillPoint', { playerId, amount });
                        professorNotify('success', 'Succès', `+${amount} point(s) de compétence envoyés à ${playerName}`);
                        setTimeout(() => {
                            if (professorState.selectedPlayer && professorState.selectedPlayer.id === playerId) {
                                postNui('professorGetPlayerSpells', { playerId });
                            }
                        }, 400);
                        closeModal();
                    }
                }
            ]);
        });
    });

    professorDOM.playersList.querySelectorAll('[data-action="remove-skillpoint-inline"]').forEach(btn => {
        btn.addEventListener('click', () => {
            const playerId = parseInt(btn.dataset.playerId, 10);
            const playerName = professorState.allPlayers.find(p => p.id === playerId)?.name || `ID ${playerId}`;
            professorState.pendingRemoveSkill = { playerId, playerName };
            if (professorState.selectedPlayer && professorState.selectedPlayer.id === playerId && Array.isArray(professorState.selectedPlayer.skills)) {
                showRemoveSkillModal(playerId, playerName, professorState.selectedPlayer.skills, professorState.selectedPlayer.skillPoints);
                professorState.pendingRemoveSkill = null;
            } else {
                postNui('professorFetchSkillLevels', { playerId });
                professorNotify('info', 'Chargement', 'Récupération des compétences...');
            }
        });
    });

    if (professorState.canManageSpells) {
        professorDOM.playersList.querySelectorAll('[data-action="apply-level"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const playerId = parseInt(btn.dataset.playerId, 10);
                const input = document.querySelector(`[data-level-input="${playerId}"]`);
                const level = input ? normalizeLevel(input.value) : 0;
                postNui('professorSetGlobalLevel', { playerId, level });
                setTimeout(() => postNui('professorGetPlayerSpells', { playerId }), 500);
            });
        });
    }
    
    // brancher la recherche inline des sorts possédés pour chaque joueur re-renderé
    attachPlayerSpellSearchEvents();
}

function closePlayerDetails(playerId) {
    professorState.expandedPlayers.delete(playerId);
    if (professorState.selectedPlayer && professorState.selectedPlayer.id === playerId) {
        professorState.selectedPlayer = null;
        professorState.selectedPlayerSpells = {};
        if (professorDOM.playerSkillpoints) {
            professorDOM.playerSkillpoints.textContent = 'Points compétence : --';
        }
    }
    professorState._lastPlayerRender = null;
    renderAllPlayers();
}

function selectPlayer(playerId, playerName) {
    const wasExpanded = professorState.expandedPlayers.has(playerId);
    
    if (wasExpanded) {
        closePlayerDetails(playerId);
        return;
    }
    
    professorState.expandedPlayers.clear();
    
    professorState.selectedPlayer = { id: playerId, name: playerName, skillPoints: undefined };
    professorState.expandedPlayers.add(playerId);
    professorState._lastPlayerRender = null;
    
    if (professorDOM.playerSkillpoints) {
        professorDOM.playerSkillpoints.textContent = 'Points compétence : --';
    }

    renderAllPlayers();
    
    postNui('professorGetPlayerSpells', { playerId });
}

function openSpellSelectionModalForPlayer(playerId, playerName, isTemporary) {
    const availableSpells = professorState.allSpells.filter(spell => {
        if (isTemporary) {
            return !professorState.tempSpells.get(playerId)?.has(spell.id);
        } else {
            return !professorState.selectedPlayerSpells[spell.id];
        }
    });
    
    if (availableSpells.length === 0) {
        postNui('professorNotify', { 
            type: 'info', 
            title: 'Information', 
            message: isTemporary ? 'Tous les sorts temporaires ont déjà été attribués' : 'Cet élève possède déjà tous les sorts disponibles'
        });
        return;
    }
    
    const list = availableSpells.map(spell => `
        <button class="list-row spell-search-item" data-spell="${spell.id}" data-spell-name="${(spell.name || spell.id).toLowerCase()}" data-spell-desc="${(spell.description || '').toLowerCase()}">
            <div class="card-main">
                ${spell.icon || spell.image ? `<img src="nui://dvr_power/html/${spell.icon || spell.image}" alt="${spell.name || spell.id}" class="spell-icon">` : ''}
                <div>
                    <div class="title">${spell.name || spell.id}</div>
                    <div class="muted">${spell.description || 'Aucune description'}</div>
                </div>
            </div>
        </button>
    `).join('');
    
    const modalTitle = isTemporary 
        ? `Attribuer un sort temporaire à ${playerName}`
        : `Attribuer un sort définitivement à ${playerName}`;
    
    const modalBody = isTemporary
        ? `
            <p class="helper-text" style="margin-bottom: 16px;">⚠️ Les sorts temporaires sont uniquement pour la durée du cours et ne sont pas inscrits dans le grimoire.</p>
            <input type="text" class="professor-input modal-search-input" id="modal-spell-search" placeholder="Rechercher un sort..." style="width: 100%; max-width: 100%; margin-bottom: 12px;">
            <div class="stack small-scroll" id="modal-spell-list">${list}</div>
        `
        : `
            <p class="helper-text" style="margin-bottom: 16px;">✅ Cette attribution sera inscrite définitivement dans le grimoire.</p>
            <input type="text" class="professor-input modal-search-input" id="modal-spell-search" placeholder="Rechercher un sort..." style="width: 100%; max-width: 100%; margin-bottom: 12px;">
            <div class="stack small-scroll" id="modal-spell-list">${list}</div>
        `;
    
    openModal(modalTitle, modalBody, [
        { label: 'Fermer', onClick: closeModal }
    ]);
    
    setTimeout(() => {
        const searchInput = document.getElementById('modal-spell-search');
        const spellItems = professorDOM.modalLayer?.querySelectorAll('.spell-search-item');
        
        if (searchInput && spellItems) {
            searchInput.addEventListener('input', (e) => {
                const searchTerm = e.target.value.toLowerCase().trim();
                
                spellItems.forEach(item => {
                    const spellName = item.dataset.spellName || '';
                    const spellDesc = item.dataset.spellDesc || '';
                    
                    if (spellName.includes(searchTerm) || spellDesc.includes(searchTerm)) {
                        item.style.display = '';
                    } else {
                        item.style.display = 'none';
                    }
                });
            });
        }
    }, 50);
    
    professorDOM.modalLayer?.querySelectorAll('[data-spell]').forEach(btn => {
        btn.addEventListener('click', () => {
            if (isTemporary) {
                selectSpellForStudent(btn.dataset.spell, playerId, playerName);
            } else {
                if (professorState.selectedPlayerSpells[btn.dataset.spell]) {
                    professorNotify('warning', 'Attention', 'Cet élève possède déjà ce sort');
                    return;
                }

                closeModal();
                setTimeout(() => {
                    selectSpellForStudentPermanent(btn.dataset.spell, playerId, playerName);
                }, 50);
                return;
            }
            closeModal();
        });
    });
}

function renderPlayerSpells(spells) {
    professorState.selectedPlayerSpells = spells || {};

    const playerId = professorState.selectedPlayer?.id;
    const inlineContainer = playerId ? document.getElementById(`player-spells-${playerId}`) : null;
    
    const targetContainer = inlineContainer || professorDOM.playerSpellsList;
    
    if (!targetContainer) return;

    const spellIds = Object.keys(professorState.selectedPlayerSpells).filter(spellId => {
        const spellData = professorState.selectedPlayerSpells[spellId];
        const spell = professorState.allSpells.find(s => s.id === spellId);
        return spell && spellData !== null && spellData !== undefined;
    });

    if (spellIds.length === 0) {
        targetContainer.innerHTML = '<div class="empty-state">Aucun sort possédé</div>';
        return;
    }

    targetContainer.innerHTML = spellIds.map(spellId => {
        const spellData = professorState.selectedPlayerSpells[spellId];
        const spell = professorState.allSpells.find(s => s.id === spellId);
        if (!spell) return '';
        
        const spellName = spell.name || spellId;
        const level = spellData && spellData.level !== undefined ? spellData.level : 0;
        const safeLevel = normalizeLevel(level);
        if (spellData) {
            spellData.level = safeLevel;
        }

        return `
            <details class="accordion" data-spell-name="${(spellName || '').toLowerCase()}" data-spell-desc="${(spell.description || '').toLowerCase()}" open>
                <summary>
                    <div class="accordion-title">
                        <span class="title">${spellName}</span>
                        <span class="muted">Niveau ${safeLevel}/${MAX_SPELL_LEVEL}</span>
                    </div>
                </summary>
                <div class="accordion-body chip-row">
                    <button class="pill-btn primary" data-action="edit-level" data-spell-id="${spellId}" data-tooltip="Modifier le niveau de ce sort (0-${MAX_SPELL_LEVEL})">Modifier le niveau</button>
                    <button class="pill-btn danger" data-action="remove-spell" data-spell-id="${spellId}" data-tooltip="Retirer définitivement ce sort de l'élève (inscrit dans le grimoire)">Retirer définitivement</button>
                </div>
            </details>
        `;
    }).filter(html => html !== '').join('');

    targetContainer.querySelectorAll('[data-action="edit-level"]').forEach(btn => {
        btn.addEventListener('click', () => {
            editSpellLevel(btn.dataset.spellId);
        });
    });

    targetContainer.querySelectorAll('[data-action="remove-spell"]').forEach(btn => {
        btn.addEventListener('click', () => {
            removePlayerSpell(btn.dataset.spellId);
        });
    });

    // Appliquer le filtre en place si un terme est déjà saisi
    if (inlineContainer) {
        const input = document.querySelector(`.player-spell-search[data-player-id="${playerId}"]`);
        if (input) {
            filterPlayerSpellsList(inlineContainer, input.value || '');
        }
    } else if (professorDOM.playerSpellSearch) {
        filterPlayerSpellsList(targetContainer, professorDOM.playerSpellSearch.value || '');
    }
}

function editSpellLevel(spellId) {
    const spellData = professorState.selectedPlayerSpells[spellId];
    if (!spellData) return;

    currentEditingSpell = { spellId, playerId: professorState.selectedPlayer.id };
    const currentLevel = normalizeLevel(spellData.level || 0);

    const spell = professorState.allSpells.find(s => s.id === spellId);
    const spellName = spell ? spell.name : spellId;
    
    openModal(`Modifier le niveau - ${spellName}`, `
        <div class="spell-level-control" style="display: block; margin: 0;">
            <div class="form-field">
                <label>Niveau (0-${MAX_SPELL_LEVEL})</label>
                <div class="level-control">
                    <input type="range" id="modal-spell-level" class="professor-slider" min="0" max="${MAX_SPELL_LEVEL}" value="${currentLevel}">
                    <span id="level-value" style="min-width: 40px; text-align: center; font-weight: 700; color: var(--accent);">${currentLevel}</span>
                </div>
            </div>
            <div class="level-info">
                <p>Niveau sélectionné: <span id="total-value" style="font-weight: 700; color: var(--accent); font-size: 16px;">${currentLevel}</span> / ${MAX_SPELL_LEVEL}</p>
            </div>
            <p class="helper-text">Les niveaux vont de 0 (débutant) à ${MAX_SPELL_LEVEL} (maîtrise complète).</p>
        </div>
    `, [
        { label: 'Valider', variant: 'primary', onClick: () => {
            const levelInput = document.getElementById('modal-spell-level');
            const levelValue = normalizeLevel(levelInput?.value);
            applySpellLevel(levelValue);
        }},
        { label: 'Annuler', onClick: closeModal }
    ]);

    const levelSlider = document.getElementById('modal-spell-level');
    const levelDisplay = document.getElementById('level-value');
    const totalDisplay = document.getElementById('total-value');

    if (!levelSlider || !levelDisplay || !totalDisplay) {
        return;
    }

    const refreshDisplay = () => {
        const lvl = normalizeLevel(levelSlider.value);
        levelSlider.value = lvl;
        levelDisplay.textContent = lvl;
        totalDisplay.textContent = lvl;
    };

    levelSlider.addEventListener('input', refreshDisplay);
    refreshDisplay();
}

function applySpellLevel(level) {
    if (!currentEditingSpell) return;

    const safeLevel = normalizeLevel(level);

    const spell = professorState.allSpells.find(s => s.id === currentEditingSpell.spellId);
    const spellName = spell ? spell.name : currentEditingSpell.spellId;

    postNui('professorSetSpellLevel', {
        playerId: currentEditingSpell.playerId,
        spellId: currentEditingSpell.spellId,
        level: safeLevel
    });

    addToHistory('Modification niveau', professorState.selectedPlayer.name, spellName, `Niveau ${safeLevel}/${MAX_SPELL_LEVEL}`);

    closeModal();
    currentEditingSpell = null;

    setTimeout(() => {
        postNui('professorGetPlayerSpells', { playerId: professorState.selectedPlayer.id });
    }, 500);
}

function removePlayerSpell(spellId) {
    const selected = professorState.selectedPlayer;
    if (!selected) {
        professorNotify('error', 'Erreur', 'Aucun élève sélectionné');
        return;
    }

    const spell = professorState.allSpells.find(s => s.id === spellId);
    if (!spell) {
        professorNotify('error', 'Erreur', 'Sort introuvable');
        return;
    }

    const spellName = spell.name || spellId;
    const spellData = professorState.selectedPlayerSpells[spellId];
    
    if (!spellData) {
        professorNotify('error', 'Erreur', 'Ce sort n\'est pas possédé par cet élève');
        return;
    }

    postNui('professorRemoveSpell', {
        playerId: professorState.selectedPlayer.id,
        spellId
    });

    delete professorState.selectedPlayerSpells[spellId];
    renderPlayerSpells(professorState.selectedPlayerSpells);

    addToHistory('Retrait sort', professorState.selectedPlayer.name, spellName);

    setTimeout(() => {
        postNui('professorGetPlayerSpells', { playerId: professorState.selectedPlayer.id });
    }, 500);
}

function addToHistory(action, playerName, spellName, details) {
    return;
}

function addToHistoryInternal() { return; }


if (professorDOM.closeBtn) {
    professorDOM.closeBtn.addEventListener('click', closeProfessorMenu);
}

if (professorDOM.tabs) {
    professorDOM.tabs.forEach(tab => {
        tab.addEventListener('click', () => {
            switchTab(tab.dataset.tab);
        });
    });
}

if (professorDOM.addSpellPermanentBtn) {
    professorDOM.addSpellPermanentBtn.addEventListener('click', () => {
        if (professorState.selectedPlayer) {
            openSpellSelectionModalForPlayer(professorState.selectedPlayer.id, professorState.selectedPlayer.name, false);
        }
    });
}

if (professorDOM.giveSkillpointBtn) {
    professorDOM.giveSkillpointBtn.addEventListener('click', () => {
        openSkillPointModal();
    });
} else {
    ensureSkillpointButton();
}

if (professorDOM.removeSkillpointBtn) {
    professorDOM.removeSkillpointBtn.addEventListener('click', () => {
        if (professorState.selectedPlayer && Array.isArray(professorState.selectedPlayer.skills)) {
            showRemoveSkillModal(
                professorState.selectedPlayer.id,
                professorState.selectedPlayer.name,
                professorState.selectedPlayer.skills,
                professorState.selectedPlayer.skillPoints
            );
        } else if (professorState.selectedPlayer) {
            professorState.pendingRemoveSkill = { playerId: professorState.selectedPlayer.id, playerName: professorState.selectedPlayer.name };
            postNui('professorFetchSkillLevels', { playerId: professorState.selectedPlayer.id });
        } else {
            professorNotify('error', 'Erreur', 'Aucun élève sélectionné');
        }
    });
}

if (professorDOM.bulkRefreshBtn) {
    professorDOM.bulkRefreshBtn.addEventListener('click', () => {
        refreshNearbyPlayers();
    });
}

if (professorDOM.bulkGiveBtn) {
    professorDOM.bulkGiveBtn.addEventListener('click', () => {
        const amountInput = professorDOM.bulkAmountInput;
        const raw = amountInput ? parseInt(amountInput.value, 10) : 1;
        const amount = Math.max(1, Math.min(50, isNaN(raw) ? 1 : raw));
        const checkboxes = professorDOM.bulkList ? professorDOM.bulkList.querySelectorAll('.bulk-check:checked') : [];
        if (!checkboxes || checkboxes.length === 0) {
            professorNotify('error', 'Erreur', 'Aucun élève sélectionné.');
            return;
        }
        checkboxes.forEach(cb => {
            const playerId = parseInt(cb.dataset.playerId, 10);
            if (!Number.isNaN(playerId)) {
                postNui('professorGiveSkillPoint', { playerId, amount });
            }
        });
        professorNotify('success', 'Succès', `+${amount} point(s) attribués à ${checkboxes.length} élève(s).`);
    });
}

const closePlayerDetailsBtn = document.getElementById('close-player-details');
if (closePlayerDetailsBtn) {
    closePlayerDetailsBtn.addEventListener('click', () => {
        if (professorState.selectedPlayer) {
            const playerId = professorState.selectedPlayer.id;
            professorState.selectedPlayer = null;
            professorState.selectedPlayerSpells = {};
            professorState.expandedPlayers.delete(playerId);
            if (professorDOM.playerSkillpoints) {
                professorDOM.playerSkillpoints.textContent = 'Points compétence : --';
            }
        }
        if (professorDOM.playerDetailsSection) {
            professorDOM.playerDetailsSection.dataset.visible = 'false';
        }
    });
}

if (professorDOM.refreshNearbyBtn) {
    professorDOM.refreshNearbyBtn.addEventListener('click', refreshNearbyPlayers);
}

if (professorDOM.includeProfessorBtn) {
    professorDOM.includeProfessorBtn.addEventListener('click', () => {
        const players = professorState.allPlayers || [];
        if (players.length === 0) {
            professorNotify('info', 'Information', 'Aucun joueur disponible pour sélection.');
            return;
        }
        openModal('Choisir le professeur', `
            <input type="text" class="professor-input modal-search-input" id="modal-professor-search" placeholder="Rechercher un joueur..." style="width: 100%; max-width: 100%; margin-bottom: 12px;">
            <div class="stack small-scroll" id="modal-professor-list">
                ${players.map(player => `
                    <button class="list-row player-search-item" data-self="${player.id}" data-player-name="${sanitizePlayerName(player).toLowerCase()}" data-player-id="${player.id}">
                        <div class="list-main">
                            <strong>${sanitizePlayerName(player)}</strong>
                            <span class="muted">ID ${player.id}</span>
                        </div>
                    </button>
                `).join('')}
            </div>
        `, [{ label: 'Fermer', onClick: closeModal }]);

        setTimeout(() => {
            const searchInput = document.getElementById('modal-professor-search');
            const playerItems = professorDOM.modalLayer?.querySelectorAll('.player-search-item');
            
            if (searchInput && playerItems) {
                searchInput.addEventListener('input', (e) => {
                    const searchTerm = e.target.value.toLowerCase().trim();
                    
                    playerItems.forEach(item => {
                        const playerName = item.dataset.playerName || '';
                        const playerId = item.dataset.playerId || '';
                        
                        if (playerName.includes(searchTerm) || playerId.includes(searchTerm)) {
                            item.style.display = '';
                        } else {
                            item.style.display = 'none';
                        }
                    });
                });
            }
        }, 50);

        professorDOM.modalLayer?.querySelectorAll('[data-self]').forEach(btn => {
            btn.addEventListener('click', () => {
                const id = parseInt(btn.dataset.self, 10);
                const player = players.find(p => p.id === id);
                professorState.professor = player || null;
                renderNearbyStudents(professorState.nearbyPlayers);
                closeModal();
            });
        });
    });
}

if (professorDOM.removeAllTempBtn) {
    professorDOM.removeAllTempBtn.addEventListener('click', removeAllTempSpells);
}

if (professorDOM.spellSearch) {
    professorDOM.spellSearch.addEventListener('input', renderAllSpells);
}

if (professorDOM.playerSearch) {
    professorDOM.playerSearch.addEventListener('input', renderAllPlayers);
}

function filterPlayerSpellsList(container, searchTerm) {
    if (!container) return;
    const term = (searchTerm || '').toLowerCase().trim();
    const items = container.querySelectorAll('.accordion');
    let visibleCount = 0;
    items.forEach(item => {
        const name = item.dataset.spellName || '';
        const desc = item.dataset.spellDesc || '';
        const match = !term || name.includes(term) || desc.includes(term);
        item.style.display = match ? '' : 'none';
        if (match) visibleCount++;
    });
}

if (professorDOM.playerSpellSearch) {
    professorDOM.playerSpellSearch.addEventListener('input', (e) => {
        const term = e.target.value;
        if (professorDOM.playerSpellsList) {
            filterPlayerSpellsList(professorDOM.playerSpellsList, term);
        }
    });
}

    if (professorDOM.playersList) {
    professorDOM.playersList.addEventListener('toggle', (event) => {
        if (event.target.tagName === 'DETAILS') {
            const playerId = parseInt(event.target.dataset.playerId, 10);
            if (!Number.isNaN(playerId)) {
                if (event.target.hasAttribute('open')) {
                    professorState.expandedPlayers.add(playerId);
                } else {
                    professorState.expandedPlayers.delete(playerId);
                }
            }

            if (professorState.selectedPlayer && professorDOM.playerDetailsSection) {
                const selectedId = professorState.selectedPlayer.id;
                if (playerId === selectedId) {
                    professorDOM.playerDetailsSection.dataset.visible = event.target.hasAttribute('open') ? 'true' : 'false';
                }
            }
        }
    }, true);
}

function attachPlayerSpellSearchEvents() {
    if (!professorDOM.playersList) return;
    const inputs = professorDOM.playersList.querySelectorAll('.player-spell-search');
    inputs.forEach(input => {
        input.addEventListener('input', (e) => {
            const term = e.target.value;
            const playerId = parseInt(input.dataset.playerId, 10);
            const container = document.getElementById(`player-spells-${playerId}`);
            if (container) {
                filterPlayerSpellsList(container, term);
            }
        });
    });
}

if (professorDOM.newClassBtn) {
    professorDOM.newClassBtn.addEventListener('click', () => openClassForm());
}

if (professorDOM.addNoteBtn) {
    professorDOM.addNoteBtn.addEventListener('click', () => openNoteModal());
}

if (professorDOM.markAttendanceBtn) {
    professorDOM.markAttendanceBtn.addEventListener('click', openAttendanceModal);
}

function removeAllPermanentSpells() {
    if (!professorState.selectedPlayer) {
        professorNotify('error', 'Erreur', 'Aucun élève sélectionné');
        return;
    }

    const spellIds = Object.keys(professorState.selectedPlayerSpells).filter(spellId => {
        const spellData = professorState.selectedPlayerSpells[spellId];
        const spell = professorState.allSpells.find(s => s.id === spellId);
        return spell && spellData !== null && spellData !== undefined;
    });

    if (spellIds.length === 0) {
        professorNotify('info', 'Information', 'Aucun sort à retirer');
        return;
    }

    professorState.massAction = { type: 'remove_all', target: professorState.selectedPlayer.name };

    spellIds.forEach(spellId => {
        postNui('professorRemoveSpell', {
            playerId: professorState.selectedPlayer.id,
            spellId
        });
    });

    addToHistory('Retrait tous sorts définitifs', professorState.selectedPlayer.name, `${spellIds.length} sort${spellIds.length > 1 ? 's' : ''}`);

    setTimeout(() => {
        postNui('professorGetPlayerSpells', { playerId: professorState.selectedPlayer.id });
        professorNotify('success', 'Succès', `Tous les sorts ont été retirés de ${professorState.selectedPlayer.name}.`);
        professorState.massAction = null;
    }, 500);
}

function resetPlayerCooldowns() {
    if (!professorState.selectedPlayer) {
        professorNotify('error', 'Erreur', 'Aucun élève sélectionné');
        return;
    }

    postNui('professorResetCooldowns', {
        playerId: professorState.selectedPlayer.id
    });

    addToHistory('Reset cooldowns', professorState.selectedPlayer.name, 'Tous les cooldowns réinitialisés');
    professorNotify('success', 'Succès', `Tous les cooldowns de ${professorState.selectedPlayer.name} ont été réinitialisés.`);
}

function addAllPermanentSpells() {
    if (!professorState.selectedPlayer) {
        professorNotify('error', 'Erreur', 'Aucun élève sélectionné');
        return;
    }
    if (!professorState.allSpells || professorState.allSpells.length === 0) {
        professorNotify('error', 'Erreur', 'Aucun sort disponible');
        return;
    }

    if (professorDOM.addAllPermanentBtn) {
        professorDOM.addAllPermanentBtn.disabled = true;
    }
    professorState.massAction = { type: 'add_all', target: professorState.selectedPlayer.name };

    professorState.allSpells.forEach(spell => {
        postNui('professorGiveSpell', {
            playerId: professorState.selectedPlayer.id,
            spellId: spell.id
        });
    });

    addToHistory('Ajout tous sorts définitifs', professorState.selectedPlayer.name, `${professorState.allSpells.length} sorts`);

    setTimeout(() => {
        postNui('professorGetPlayerSpells', { playerId: professorState.selectedPlayer.id });
        if (professorDOM.addAllPermanentBtn) {
            professorDOM.addAllPermanentBtn.disabled = false;
        }
        professorNotify('success', 'Succès', `Tous les sorts ont été ajoutés à ${professorState.selectedPlayer.name}.`);
        professorState.massAction = null;
    }, 600);
}

function applyGlobalLevelsToAll() {
    const selected = professorState.selectedPlayer
    if (!selected) {
        professorNotify('error', 'Erreur', 'Aucun élève sélectionné');
        return;
    }

    const levelInput = professorDOM.globalLevelInput ? parseInt(professorDOM.globalLevelInput.value, 10) : 0;

    const safeLevel = normalizeLevel(levelInput || 0);
    const targetPlayerId = selected.id;
    const targetPlayerName = selected.name || 'élève';

    if (professorDOM.applyGlobalLevelsBtn) {
        professorDOM.applyGlobalLevelsBtn.disabled = true;
    }
    professorState.massAction = { type: 'mass_level', target: professorState.selectedPlayer.name, level: safeLevel };

    const spellIds = Object.keys(professorState.selectedPlayerSpells || {});
    if (spellIds.length === 0) {
        professorNotify('info', 'Information', 'Aucun sort à modifier');
        if (professorDOM.applyGlobalLevelsBtn) {
            professorDOM.applyGlobalLevelsBtn.disabled = false;
        }
        professorState.massAction = null;
        return;
    }

    spellIds.forEach(spellId => {
        postNui('professorSetSpellLevel', {
            playerId: professorState.selectedPlayer.id,
            spellId,
            level: safeLevel
        });
    });

    addToHistory('Modification globale niveaux', professorState.selectedPlayer.name, `${spellIds.length} sorts`, `Niveau ${safeLevel}/${MAX_SPELL_LEVEL}`);

    setTimeout(() => {
        if (targetPlayerId) {
            postNui('professorGetPlayerSpells', { playerId: targetPlayerId });
        }
        if (professorDOM.applyGlobalLevelsBtn) {
            professorDOM.applyGlobalLevelsBtn.disabled = false;
        }
        professorNotify('success', 'Succès', `Tous les sorts de ${targetPlayerName} ont été mis à jour au niveau ${safeLevel}/${MAX_SPELL_LEVEL}.`);
        professorState.massAction = null;
    }, 800);
}

if (professorDOM.removeAllPermanentBtn) {
    professorDOM.removeAllPermanentBtn.addEventListener('click', removeAllPermanentSpells);
}

if (professorDOM.addAllPermanentBtn) {
    professorDOM.addAllPermanentBtn.addEventListener('click', addAllPermanentSpells);
}

if (professorDOM.applyGlobalLevelsBtn) {
    professorDOM.applyGlobalLevelsBtn.addEventListener('click', applyGlobalLevelsToAll);
}

function setAllSpellsMaxLevel() {
    const selected = professorState.selectedPlayer;
    if (!selected) {
        professorNotify('error', 'Erreur', 'Aucun élève sélectionné');
        return;
    }

    const spellIds = Object.keys(professorState.selectedPlayerSpells || {});
    if (spellIds.length === 0) {
        professorNotify('info', 'Information', 'Aucun sort à modifier');
        return;
    }

    if (professorDOM.setMaxLevelBtn) {
        professorDOM.setMaxLevelBtn.disabled = true;
    }

    spellIds.forEach(spellId => {
        postNui('professorSetSpellLevel', {
            playerId: selected.id,
            spellId,
            level: MAX_SPELL_LEVEL
        });
    });

    addToHistory('Niveau max tous sorts', selected.name, `${spellIds.length} sorts`, `Niveau ${MAX_SPELL_LEVEL}`);

    setTimeout(() => {
        postNui('professorGetPlayerSpells', { playerId: selected.id });
        if (professorDOM.setMaxLevelBtn) {
            professorDOM.setMaxLevelBtn.disabled = false;
        }
        professorNotify('success', 'Succès', `Tous les sorts de ${selected.name} sont maintenant au niveau max (${MAX_SPELL_LEVEL}).`);
    }, 600);
}

if (professorDOM.setMaxLevelBtn) {
    professorDOM.setMaxLevelBtn.addEventListener('click', setAllSpellsMaxLevel);
}

if (professorDOM.resetCooldownBtn) {
    professorDOM.resetCooldownBtn.addEventListener('click', resetPlayerCooldowns);
}

if (professorDOM.clearHistoryBtn) {
    professorDOM.clearHistoryBtn.addEventListener('click', clearHistory);
}

document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape' && professorState.visible) {
        event.preventDefault();
        event.stopPropagation();
        closeProfessorMenu();
        return false;
    }
}, true);

(function() {
    let activeTooltip = null;
    
    function createTooltip(element, text) {
        if (activeTooltip) {
            activeTooltip.remove();
        }
        
        const tooltip = document.createElement('div');
        tooltip.className = 'tooltip-fixed';
        tooltip.textContent = text;
        tooltip.style.cssText = `
            position: fixed;
            padding: 10px 14px;
            background: var(--accent);
            color: var(--ink);
            border: 1px solid var(--accent-strong);
            border-radius: 6px;
            font-size: 12px;
            white-space: normal;
            max-width: 300px;
            z-index: 100000;
            pointer-events: none;
            font-weight: 600;
            line-height: 1.4;
            text-align: center;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
            opacity: 0;
            transition: opacity 0.1s ease;
        `;
        document.body.appendChild(tooltip);
        
        const rect = element.getBoundingClientRect();
        const tooltipRect = tooltip.getBoundingClientRect();
        
        let left = rect.left + (rect.width / 2) - (tooltipRect.width / 2);
        let top = rect.top - tooltipRect.height - 10;
        
        if (left < 10) left = 10;
        if (left + tooltipRect.width > window.innerWidth - 10) {
            left = window.innerWidth - tooltipRect.width - 10;
        }
        if (top < 10) {
            top = rect.bottom + 10;
        }
        
        tooltip.style.left = left + 'px';
        tooltip.style.top = top + 'px';
        
        setTimeout(() => {
            tooltip.style.opacity = '1';
        }, 10);
        
        activeTooltip = tooltip;
        return tooltip;
    }
    
    function removeTooltip() {
        if (activeTooltip) {
            activeTooltip.style.opacity = '0';
            setTimeout(() => {
                if (activeTooltip && activeTooltip.parentNode) {
                    activeTooltip.remove();
                }
                activeTooltip = null;
            }, 100);
        }
    }
    
    document.addEventListener('mouseover', function(e) {
        const target = e.target.closest('[data-tooltip]');
        if (target && target.getAttribute('data-tooltip')) {
            const text = target.getAttribute('data-tooltip');
            createTooltip(target, text);
        } else {
            removeTooltip();
        }
    }, true);
    
    document.addEventListener('mouseout', function(e) {
        const target = e.target.closest('[data-tooltip]');
        if (!target || !target.getAttribute('data-tooltip')) {
            removeTooltip();
        }
    }, true);
    
    document.addEventListener('mousemove', function(e) {
        if (activeTooltip) {
            const target = document.elementFromPoint(e.clientX, e.clientY);
            const tooltipElement = target?.closest('[data-tooltip]');
            if (tooltipElement && tooltipElement.getAttribute('data-tooltip')) {
                const rect = tooltipElement.getBoundingClientRect();
                const tooltipRect = activeTooltip.getBoundingClientRect();
                
                let left = rect.left + (rect.width / 2) - (tooltipRect.width / 2);
                let top = rect.top - tooltipRect.height - 10;
                
                if (left < 10) left = 10;
                if (left + tooltipRect.width > window.innerWidth - 10) {
                    left = window.innerWidth - tooltipRect.width - 10;
                }
                if (top < 10) {
                    top = rect.bottom + 10;
                }
                
                activeTooltip.style.left = left + 'px';
                activeTooltip.style.top = top + 'px';
            }
        }
    });
})();
