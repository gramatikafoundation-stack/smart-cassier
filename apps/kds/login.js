const $ = id => document.getElementById(id);
let navigating = false;

const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

async function kds(body) {
  const response = await fetch('/api/kds', {
    method: 'POST',
    credentials: 'same-origin',
    cache: 'no-store',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || data?.ok === false) throw new Error(data?.error || 'Permintaan gagal.');
  return data;
}

async function confirmSession() {
  let lastError = null;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      const session = await kds({ action: 'session' });
      if (session?.ok) return true;
    } catch (error) {
      lastError = error;
      if (error?.message && error.message !== 'invalid_session') throw error;
    }
    if (attempt < 2) await wait(60 * (attempt + 1));
  }
  throw lastError || new Error('session_not_ready');
}

$('loginForm').addEventListener('submit', async event => {
  event.preventDefault();
  if (navigating) return;

  const button = $('loginButton');
  const message = $('loginMessage');
  button.disabled = true;
  button.textContent = 'Memeriksa…';
  message.textContent = '';

  try {
    await kds({
      action: 'login',
      email: $('email').value.trim().toLowerCase(),
      password: $('password').value
    });

    button.textContent = 'Membuka KDS…';
    await confirmSession();

    navigating = true;
    sessionStorage.setItem('rohmat:kds:justLoggedIn', '1');
    location.replace('/kds');
  } catch (error) {
    message.textContent = error.message === 'rate_limited'
      ? 'Terlalu banyak percobaan. Coba lagi beberapa saat.'
      : error.message === 'session_not_ready' || error.message === 'invalid_session'
        ? 'Sesi belum siap. Silakan klik Masuk sekali lagi.'
        : 'Email atau kata sandi tidak sesuai.';
  } finally {
    if (!navigating) {
      button.disabled = false;
      button.textContent = 'Masuk ke Kitchen Display System';
    }
  }
});
