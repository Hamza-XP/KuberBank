'use strict';

// API Configuration
const API_BASE_URL = window.location.hostname === 'localhost' 
  ? 'http://localhost:3000' 
  : window.location.hostname.includes('github.io')
  ? 'http://localhost:3000'  // For GitHub Pages demo
  : 'https://api.kuberbank.io';

// DOM Elements
const modal = document.querySelector('.modal');
const overlay = document.querySelector('.overlay');
const btnCloseModal = document.querySelector('.btn--close-modal');
const btnsOpenModal = document.querySelectorAll('.btn--show-modal');
const btnscrollto = document.querySelector('.btn--scroll-to');
const section1 = document.querySelector('#section--1');
const nav = document.querySelector('.nav');
const header = document.querySelector('.header');

// Application State
const state = {
  currentAccount: null,
  transactions: [],
  isLoggedIn: false,
  isDemo: false
};

// Utility Functions
const showNotification = (message, type = 'info') => {
  // Remove existing notifications
  const existingNotif = document.querySelector('.notification');
  if (existingNotif) existingNotif.remove();
  
  const notification = document.createElement('div');
  notification.className = `notification notification--${type}`;
  notification.innerHTML = `
    <div class="notification__content">
      <span class="notification__icon">${type === 'success' ? '✓' : type === 'error' ? '✗' : 'ℹ'}</span>
      <span class="notification__message">${message}</span>
    </div>
  `;
  document.body.appendChild(notification);
  
  setTimeout(() => {
    notification.classList.add('notification--show');
  }, 10);
  
  setTimeout(() => {
    notification.classList.remove('notification--show');
    setTimeout(() => notification.remove(), 300);
  }, 4000);
};

const formatCurrency = (value) => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD'
  }).format(value);
};

const formatDate = (date) => {
  const now = new Date();
  const txDate = new Date(date);
  const diffMs = now - txDate;
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);
  
  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins} min ago`;
  if (diffHours < 24) return `${diffHours} hours ago`;
  if (diffDays < 7) return `${diffDays} days ago`;
  
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: txDate.getFullYear() !== now.getFullYear() ? 'numeric' : undefined
  }).format(txDate);
};

// API Functions
const api = {
  async createAccount(data) {
    try {
      const response = await fetch(`${API_BASE_URL}/api/accounts`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      });
      
      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Failed to create account');
      }
      return await response.json();
    } catch (error) {
      console.error('API Error:', error);
      throw error;
    }
  },
  
  async getAccount(accountNumber) {
    try {
      const response = await fetch(`${API_BASE_URL}/api/accounts/${accountNumber}`);
      if (!response.ok) throw new Error('Account not found');
      return await response.json();
    } catch (error) {
      console.error('API Error:', error);
      throw error;
    }
  },
  
  async getTransactions(accountNumber) {
    try {
      const response = await fetch(`${API_BASE_URL}/api/accounts/${accountNumber}/transactions`);
      if (!response.ok) throw new Error('Failed to fetch transactions');
      return await response.json();
    } catch (error) {
      console.error('API Error:', error);
      throw error;
    }
  },
  
  async createTransaction(data) {
    try {
      const response = await fetch(`${API_BASE_URL}/api/transactions`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      });
      
      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Transaction failed');
      }
      return await response.json();
    } catch (error) {
      console.error('API Error:', error);
      throw error;
    }
  },
  
  async transfer(data) {
    try {
      const response = await fetch(`${API_BASE_URL}/api/transfers`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      });
      
      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Transfer failed');
      }
      return await response.json();
    } catch (error) {
      console.error('API Error:', error);
      throw error;
    }
  }
};

// Demo Mode (when backend is not available)
const demoAPI = {
  accounts: new Map(),
  transactions: new Map(),
  
  async createAccount(data) {
    await new Promise(resolve => setTimeout(resolve, 500));
    const accountNumber = `KB${Date.now()}${Math.floor(Math.random() * 10000)}`;
    const account = {
      userId: Math.floor(Math.random() * 10000),
      accountNumber,
      balance: data.initialDeposit || 0,
      firstName: data.firstName,
      lastName: data.lastName,
      email: data.email
    };
    this.accounts.set(accountNumber, account);
    this.transactions.set(accountNumber, [{
      id: 1,
      type: 'deposit',
      amount: data.initialDeposit || 0,
      description: 'Initial deposit',
      status: 'completed',
      created_at: new Date().toISOString()
    }]);
    return { success: true, data: account };
  },
  
  async getAccount(accountNumber) {
    await new Promise(resolve => setTimeout(resolve, 300));
    const account = this.accounts.get(accountNumber);
    if (!account) throw new Error('Account not found');
    return { success: true, data: account };
  },
  
  async getTransactions(accountNumber) {
    await new Promise(resolve => setTimeout(resolve, 300));
    const txs = this.transactions.get(accountNumber) || [];
    return { success: true, data: txs };
  },
  
  async createTransaction(data) {
    await new Promise(resolve => setTimeout(resolve, 500));
    const account = this.accounts.get(data.accountNumber);
    if (!account) throw new Error('Account not found');
    
    let newBalance = account.balance;
    if (data.type === 'deposit') {
      newBalance += parseFloat(data.amount);
    } else if (data.type === 'withdrawal') {
      if (account.balance < data.amount) throw new Error('Insufficient funds');
      newBalance -= parseFloat(data.amount);
    }
    
    account.balance = newBalance;
    const txs = this.transactions.get(data.accountNumber) || [];
    txs.unshift({
      id: txs.length + 1,
      type: data.type,
      amount: parseFloat(data.amount),
      description: data.description,
      status: 'completed',
      created_at: new Date().toISOString()
    });
    
    return { success: true, data: { newBalance, transactionId: txs[0].id, timestamp: txs[0].created_at } };
  },
  
  async transfer(data) {
    await new Promise(resolve => setTimeout(resolve, 500));
    const fromAccount = this.accounts.get(data.fromAccount);
    const toAccount = this.accounts.get(data.toAccount);
    
    if (!fromAccount) throw new Error('Source account not found');
    if (!toAccount) throw new Error('Destination account not found');
    if (fromAccount.balance < data.amount) throw new Error('Insufficient funds');
    
    fromAccount.balance -= parseFloat(data.amount);
    toAccount.balance += parseFloat(data.amount);
    
    const fromTxs = this.transactions.get(data.fromAccount) || [];
    fromTxs.unshift({
      id: fromTxs.length + 1,
      type: 'withdrawal',
      amount: parseFloat(data.amount),
      description: `Transfer to ${data.toAccount}: ${data.description}`,
      status: 'completed',
      created_at: new Date().toISOString()
    });
    
    const toTxs = this.transactions.get(data.toAccount) || [];
    toTxs.unshift({
      id: toTxs.length + 1,
      type: 'deposit',
      amount: parseFloat(data.amount),
      description: `Transfer from ${data.fromAccount}: ${data.description}`,
      status: 'completed',
      created_at: new Date().toISOString()
    });
    
    return { success: true, message: 'Transfer completed' };
  }
};

// Detect if we should use demo mode
const useAPI = state.isDemo ? demoAPI : api;

// Modal Functions
const openModal = function (e) {
  e.preventDefault();
  modal.classList.remove('hidden');
  overlay.classList.remove('hidden');
};

const closeModal = function () {
  modal.classList.add('hidden');
  overlay.classList.add('hidden');
};

btnsOpenModal.forEach(btn => btn.addEventListener('click', openModal));
btnCloseModal.addEventListener('click', closeModal);
overlay.addEventListener('click', closeModal);

document.addEventListener('keydown', function (e) {
  if (e.key === 'Escape' && !modal.classList.contains('hidden')) {
    closeModal();
  }
});

// Account Creation Form
const modalForm = document.querySelector('.modal__form');
if (modalForm) {
  modalForm.addEventListener('submit', async function(e) {
    e.preventDefault();
    
    const inputs = this.querySelectorAll('input');
    const formData = {
      firstName: inputs[0].value.trim(),
      lastName: inputs[1].value.trim(),
      email: inputs[2].value.trim(),
      initialDeposit: 1000
    };
    
    if (!formData.firstName || !formData.lastName || !formData.email) {
      showNotification('Please fill in all fields', 'error');
      return;
    }
    
    try {
      showNotification('Creating your account...', 'info');
      const result = await useAPI.createAccount(formData);
      
      if (result.success) {
        showNotification(`Account created! Number: ${result.data.accountNumber}`, 'success');
        state.currentAccount = result.data;
        state.isLoggedIn = true;
        
        localStorage.setItem('accountNumber', result.data.accountNumber);
        
        closeModal();
        this.reset();
        showDashboard();
      }
    } catch (error) {
      console.error('Account creation error:', error);
      showNotification(error.message || 'Failed to create account. Please try again.', 'error');
    }
  });
}

// Show Dashboard
const showDashboard = async () => {
  if (!state.currentAccount) return;
  
  // Hide marketing sections, show dashboard
  const sections = document.querySelectorAll('.section');
  sections.forEach(s => s.style.display = 'none');
  
  // Check if dashboard exists
  let dashboard = document.querySelector('.dashboard');
  if (!dashboard) {
    dashboard = document.createElement('section');
    dashboard.className = 'section dashboard';
    dashboard.innerHTML = `
      <div class="dashboard__container">
        <div class="dashboard__header">
          <div class="dashboard__welcome">
            <h2>Welcome back, <span class="dashboard__name">${state.currentAccount.firstName || state.currentAccount.first_name || 'User'}</span>! 👋</h2>
            <p class="dashboard__subtitle">Manage your finances with KuberBank</p>
          </div>
          <button class="btn btn--logout" id="logout-btn">Logout</button>
        </div>
        
        <div class="dashboard__summary">
          <div class="summary-card">
            <div class="summary-card__icon summary-card__icon--balance">💰</div>
            <div class="summary-card__content">
              <p class="summary-card__label">Current Balance</p>
              <h3 class="summary-card__value" id="account-balance">${formatCurrency(state.currentAccount.balance)}</h3>
            </div>
          </div>
          
          <div class="summary-card">
            <div class="summary-card__icon summary-card__icon--account">🏦</div>
            <div class="summary-card__content">
              <p class="summary-card__label">Account Number</p>
              <h3 class="summary-card__value summary-card__value--small" id="account-number">${state.currentAccount.accountNumber || state.currentAccount.account_number}</h3>
            </div>
          </div>
          
          <div class="summary-card">
            <div class="summary-card__icon summary-card__icon--email">📧</div>
            <div class="summary-card__content">
              <p class="summary-card__label">Email</p>
              <h3 class="summary-card__value summary-card__value--small">${state.currentAccount.email}</h3>
            </div>
          </div>
        </div>
        
        <div class="dashboard__actions">
          <div class="action-card">
            <div class="action-card__header">
              <div class="action-card__icon action-card__icon--deposit">⬇️</div>
              <h3>Deposit Money</h3>
            </div>
            <form id="deposit-form" class="action-form">
              <input type="number" placeholder="Amount ($)" min="0.01" step="0.01" required>
              <input type="text" placeholder="Description (optional)">
              <button type="submit" class="btn btn--action">Deposit</button>
            </form>
          </div>
          
          <div class="action-card">
            <div class="action-card__header">
              <div class="action-card__icon action-card__icon--withdraw">⬆️</div>
              <h3>Withdraw Money</h3>
            </div>
            <form id="withdraw-form" class="action-form">
              <input type="number" placeholder="Amount ($)" min="0.01" step="0.01" required>
              <input type="text" placeholder="Description (optional)">
              <button type="submit" class="btn btn--action">Withdraw</button>
            </form>
          </div>
          
          <div class="action-card">
            <div class="action-card__header">
              <div class="action-card__icon action-card__icon--transfer">🔄</div>
              <h3>Transfer Funds</h3>
            </div>
            <form id="transfer-form" class="action-form">
              <input type="text" placeholder="To Account Number" required>
              <input type="number" placeholder="Amount ($)" min="0.01" step="0.01" required>
              <input type="text" placeholder="Description (optional)">
              <button type="submit" class="btn btn--action">Transfer</button>
            </form>
          </div>
        </div>
        
        <div class="dashboard__transactions">
          <div class="transactions__header">
            <h3>Recent Transactions</h3>
            <div class="transactions__filter">
              <button class="filter-btn filter-btn--active" data-filter="all">All</button>
              <button class="filter-btn" data-filter="deposit">Deposits</button>
              <button class="filter-btn" data-filter="withdrawal">Withdrawals</button>
            </div>
          </div>
          <div id="transactions-list" class="transactions-list">
            <div class="loading">Loading transactions...</div>
          </div>
        </div>
      </div>
    `;
    
    header.insertAdjacentElement('afterend', dashboard);
    setupDashboardHandlers();
  } else {
    dashboard.style.display = 'block';
    // Update values
    document.getElementById('account-balance').textContent = formatCurrency(state.currentAccount.balance);
    document.querySelector('.dashboard__name').textContent = state.currentAccount.firstName || state.currentAccount.first_name || 'User';
  }
  
  // Load transactions
  await loadTransactions();
  
  // Scroll to dashboard
  dashboard.scrollIntoView({ behavior: 'smooth' });
};

// Setup Dashboard Event Handlers
const setupDashboardHandlers = () => {
  // Logout button
  document.getElementById('logout-btn').addEventListener('click', () => {
    state.currentAccount = null;
    state.isLoggedIn = false;
    localStorage.removeItem('accountNumber');
    
    document.querySelector('.dashboard').style.display = 'none';
    document.querySelectorAll('.section').forEach(s => s.style.display = 'block');
    
    showNotification('Logged out successfully', 'success');
    header.scrollIntoView({ behavior: 'smooth' });
  });
  
  // Deposit form
  document.getElementById('deposit-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const inputs = e.target.querySelectorAll('input');
    const amount = parseFloat(inputs[0].value);
    const description = inputs[1].value || 'Deposit via dashboard';
    
    try {
      showNotification('Processing deposit...', 'info');
      const result = await useAPI.createTransaction({
        accountNumber: state.currentAccount.accountNumber || state.currentAccount.account_number,
        type: 'deposit',
        amount,
        description
      });
      
      if (result.success) {
        showNotification(`Deposited ${formatCurrency(amount)} successfully!`, 'success');
        state.currentAccount.balance = result.data.newBalance;
        document.getElementById('account-balance').textContent = formatCurrency(result.data.newBalance);
        await loadTransactions();
        e.target.reset();
      }
    } catch (error) {
      showNotification(error.message || 'Deposit failed', 'error');
    }
  });
  
  // Withdraw form
  document.getElementById('withdraw-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const inputs = e.target.querySelectorAll('input');
    const amount = parseFloat(inputs[0].value);
    const description = inputs[1].value || 'Withdrawal via dashboard';
    
    if (amount > state.currentAccount.balance) {
      showNotification('Insufficient funds', 'error');
      return;
    }
    
    try {
      showNotification('Processing withdrawal...', 'info');
      const result = await useAPI.createTransaction({
        accountNumber: state.currentAccount.accountNumber || state.currentAccount.account_number,
        type: 'withdrawal',
        amount,
        description
      });
      
      if (result.success) {
        showNotification(`Withdrew ${formatCurrency(amount)} successfully!`, 'success');
        state.currentAccount.balance = result.data.newBalance;
        document.getElementById('account-balance').textContent = formatCurrency(result.data.newBalance);
        await loadTransactions();
        e.target.reset();
      }
    } catch (error) {
      showNotification(error.message || 'Withdrawal failed', 'error');
    }
  });
  
  // Transfer form
  document.getElementById('transfer-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const inputs = e.target.querySelectorAll('input');
    const toAccount = inputs[0].value.trim();
    const amount = parseFloat(inputs[1].value);
    const description = inputs[2].value || 'Transfer via dashboard';
    
    if (toAccount === (state.currentAccount.accountNumber || state.currentAccount.account_number)) {
      showNotification('Cannot transfer to the same account', 'error');
      return;
    }
    
    if (amount > state.currentAccount.balance) {
      showNotification('Insufficient funds', 'error');
      return;
    }
    
    try {
      showNotification('Processing transfer...', 'info');
      const result = await useAPI.transfer({
        fromAccount: state.currentAccount.accountNumber || state.currentAccount.account_number,
        toAccount,
        amount,
        description
      });
      
      if (result.success) {
        showNotification(`Transferred ${formatCurrency(amount)} successfully!`, 'success');
        // Refresh account data
        const accountData = await useAPI.getAccount(state.currentAccount.accountNumber || state.currentAccount.account_number);
        state.currentAccount.balance = accountData.data.balance;
        document.getElementById('account-balance').textContent = formatCurrency(accountData.data.balance);
        await loadTransactions();
        e.target.reset();
      }
    } catch (error) {
      showNotification(error.message || 'Transfer failed', 'error');
    }
  });
  
  // Transaction filter
  document.querySelectorAll('.filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('filter-btn--active'));
      btn.classList.add('filter-btn--active');
      
      const filter = btn.dataset.filter;
      document.querySelectorAll('.transaction').forEach(tx => {
        if (filter === 'all' || tx.dataset.type === filter) {
          tx.style.display = 'flex';
        } else {
          tx.style.display = 'none';
        }
      });
    });
  });
};

// Load Transactions
const loadTransactions = async () => {
  try {
    const result = await useAPI.getTransactions(state.currentAccount.accountNumber || state.currentAccount.account_number);
    
    if (result.success) {
      state.transactions = result.data;
      
      const transactionsList = document.getElementById('transactions-list');
      if (state.transactions.length === 0) {
        transactionsList.innerHTML = '<div class="empty-state">No transactions yet. Start by making a deposit!</div>';
      } else {
        transactionsList.innerHTML = state.transactions.map(tx => `
          <div class="transaction" data-type="${tx.type}">
            <div class="transaction__icon transaction__icon--${tx.type}">
              ${tx.type === 'deposit' ? '⬇️' : '⬆️'}
            </div>
            <div class="transaction__details">
              <p class="transaction__type">${tx.type.charAt(0).toUpperCase() + tx.type.slice(1)}</p>
              <p class="transaction__description">${tx.description || 'No description'}</p>
            </div>
            <div class="transaction__amount transaction__amount--${tx.type}">
              ${tx.type === 'deposit' ? '+' : '-'}${formatCurrency(tx.amount)}
            </div>
            <div class="transaction__date">${formatDate(tx.created_at)}</div>
          </div>
        `).join('');
      }
    }
  } catch (error) {
    console.error('Failed to load transactions:', error);
    document.getElementById('transactions-list').innerHTML = '<div class="error-state">Failed to load transactions</div>';
  }
};

// Check for existing session on page load
const checkSession = async () => {
  const storedAccountNumber = localStorage.getItem('accountNumber');
  if (storedAccountNumber) {
    try {
      const result = await useAPI.getAccount(storedAccountNumber);
      if (result.success) {
        state.currentAccount = result.data;
        state.isLoggedIn = true;
        showDashboard();
      }
    } catch (error) {
      localStorage.removeItem('accountNumber');
      console.log('Session expired or invalid');
    }
  }
};

// Try to connect to backend, fallback to demo mode
const initializeApp = async () => {
  try {
    const response = await fetch(`${API_BASE_URL}/health`, { signal: AbortSignal.timeout(5000) });
    if (response.ok) {
      console.log('✅ Connected to KuberBank API');
      state.isDemo = false;
    } else {
      throw new Error('API not healthy');
    }
  } catch (error) {
    console.log('⚠️ Backend not available, using demo mode');
    state.isDemo = true;
    showNotification('Running in demo mode - data is stored locally', 'info');
  }
  
  await checkSession();
};

// Smooth Scrolling
btnscrollto?.addEventListener('click', function (e) {
  section1.scrollIntoView({ behavior: 'smooth' });
});

// Page Navigation
document.querySelector('.nav__links')?.addEventListener('click', function (e) {
  if (e.target.classList.contains('nav__link')) {
    e.preventDefault();
    const id = e.target.getAttribute('href');
    if (id && id.startsWith('#')) {
      document.querySelector(id)?.scrollIntoView({ behavior: 'smooth' });
    }
  }
});

// Tabbed Component
const tabsContainer = document.querySelector('.operations__tab-container');
const tabs = document.querySelectorAll('.operations__tab');
const tabsContent = document.querySelectorAll('.operations__content');

tabsContainer?.addEventListener('click', function (e) {
  const clicked = e.target.closest('.operations__tab');
  if (!clicked) return;
  
  tabs.forEach(t => t.classList.remove('operations__tab--active'));
  tabsContent.forEach(c => c.classList.remove('operations__content--active'));
  
  clicked.classList.add('operations__tab--active');
  document
    .querySelector(`.operations__content--${clicked.dataset.tab}`)
    ?.classList.add('operations__content--active');
});

// Menu fade animation
const handler = function (ev, opa) {
  if (ev.target.classList.contains('nav__link')) {
    const link = ev.target;
    const linksiblings = link.closest('.nav').querySelectorAll('.nav__link');
    const logo = link.closest('.nav').querySelector('.nav__logo');

    linksiblings.forEach(function (ele) {
      if (ele !== link) {
        ele.style.setProperty('opacity', opa);
      }
    });
  }
};
nav.addEventListener('mouseover', function (ev) {
  handler(ev, 0.5);
});
nav.addEventListener('mouseout', function (ev) {
  handler(ev, 1);
});

// Sticky Navigation
const navHeight = nav.getBoundingClientRect().height;

const stickyNav = function (entries) {
  const [entry] = entries;
  if (!entry.isIntersecting) nav.classList.add('sticky');
  else nav.classList.remove('sticky');
};

const headerObserver = new IntersectionObserver(stickyNav, {
  root: null,
  threshold: 0,
  rootMargin: `-${navHeight}px`,
});

if (window.screen.availWidth > 700) {
  headerObserver.observe(header);
}

// Reveal Sections
const allsections = document.querySelectorAll('.section');

const revealSection = function (entries, observer) {
  const [entry] = entries;
  if (!entry.isIntersecting) return;
  entry.target.classList.remove('section--hidden');
  observer.unobserve(entry.target);
};

const sectionObserver = new IntersectionObserver(revealSection, {
  root: null,
  threshold: 0.15,
});

allsections.forEach(function (section) {
  sectionObserver.observe(section);
  section.classList.add('section--hidden');
});

// Lazy Loading Images
const imgtg = document.querySelectorAll('img[data-src]');

const lazyimg = function (entries, observer) {
  const [entry] = entries;
  if (!entry.isIntersecting) return;
  
  entry.target.src = entry.target.dataset.src;
  entry.target.addEventListener('load', function () {
    entry.target.classList.remove('lazy-img');
  });
  observer.unobserve(entry.target);
};

const imgobs = new IntersectionObserver(lazyimg, {
  root: null,
  threshold: 0,
  rootMargin: '200px',
});
imgtg.forEach(function (img) {
  imgobs.observe(img);
});

// Slider Component
const slider1 = function () {
  const btnLeft = document.querySelector('.slider__btn--left');
  const btnRight = document.querySelector('.slider__btn--right');
  const slides = document.querySelectorAll('.slide');
  const dotcontainer = document.querySelector('.dots');

  if (!slides.length) return;

  const createdots = function () {
    slides.forEach(function (_, ind) {
      dotcontainer.insertAdjacentHTML(
        'beforeend',
        `<button class="dots__dot" data-slide="${ind}"></button>`
      );
    });
  };

  const activatedots = function (slide) {
    document.querySelectorAll('.dots__dot').forEach(function (ele) {
      ele.classList.remove('dots__dot--active');
    });
    document
      .querySelector(`.dots__dot[data-slide="${slide}"]`)
      ?.classList.add('dots__dot--active');
  };

  let currentslide = 0;
  const maxSlides = slides.length - 1;

  const gotoslide = function (slide) {
    slides.forEach((slid, ind) => {
      slid.style.transform = `translateX(${100 * (ind - slide)}%)`;
    });
  };

  const nextslide = function () {
    if (currentslide === maxSlides) {
      currentslide = 0;
    } else {
      currentslide++;
    }
    gotoslide(currentslide);
    activatedots(currentslide);
  };

  const prevslide = function () {
    if (currentslide === 0) {
      currentslide = maxSlides;
    } else {
      currentslide--;
    }
    gotoslide(currentslide);
    activatedots(currentslide);
  };

  const init = function () {
    gotoslide(0);
    createdots();
    activatedots(0);
  };
  init();

  btnRight?.addEventListener('click', nextslide);
  btnLeft?.addEventListener('click', prevslide);

  document.addEventListener('keydown', function (e) {
    if (e.key === 'ArrowLeft') prevslide();
    e.key === 'ArrowRight' && nextslide();
  });

  dotcontainer?.addEventListener('click', function (e) {
    if (e.target.classList.contains('dots__dot')) {
      const slides = e.target.dataset.slide;
      gotoslide(slides);
      activatedots(slides);
    }
  });
};
slider1();

// Initialize the application
initializeApp();