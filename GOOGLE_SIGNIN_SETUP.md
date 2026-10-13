# Sign in with Google: setup

The app is ready: Settings › Account (and anywhere the Account sheet opens)
shows **Sign in with Google** under **Sign in with Apple**. It uses Supabase's
own Google sign-in in a secure Safari sheet (OAuth with PKCE), so there's no
Google SDK in the app and the app never sees a Google password or token.
These steps switch it on. About 15 minutes. Never paste the client secret in
a chat or commit it to git.

How it works: the app opens
`https://ulbpwygzwchsnvdeeife.supabase.co/auth/v1/authorize?provider=google…`,
Supabase sends the person to Google, Google sends them back to Supabase
(`…/auth/v1/callback`), and Supabase returns them to the app at
`versely://auth-callback?code=…`. The app trades that one-time code, with a
secret only it knows, for a session. Until the steps below are done, the
button opens a Supabase error page instead.

## 1. Google Cloud Console

Go to [console.cloud.google.com](https://console.cloud.google.com) and sign in
with the Google account that should own the app's sign-in.

1. **Create a project**: project picker (top left) → **New Project** → name
   "Versely" → Create, then select it.
2. **OAuth consent screen** (menu → **APIs & Services** → **OAuth consent
   screen**; newer consoles call it **Google Auth Platform** → Get started):
   - **App information**: App name **Versely**, User support email (yours).
   - **Audience**: **External**.
   - **Contact information**: your email. Agree and **Create**.
   - **Branding**: upload the app icon (120 × 120 PNG), Application home
     page, **Privacy policy** URL and **Terms of service** URL (the same
     links as in App Store Connect). Under **Authorized domains** add
     `supabase.co` and the domain of your privacy policy.
   - **Data Access** (or "Scopes") → **Add or remove scopes** → tick only
     `openid`, `.../auth/userinfo.email` and `.../auth/userinfo.profile` →
     Update → Save. These are non-sensitive scopes, so Google needs no app
     verification beyond its quick branding review (which only matters if you
     want your name and logo shown on Google's screen).
   - **Audience** → Publishing status → **Publish app** → confirm, so it's
     **In production**. (While "Testing", only listed test users can sign in.)
3. **Credentials** (APIs & Services → **Credentials**, or Google Auth
   Platform → **Clients**) → **Create credentials** → **OAuth client ID**:
   - Application type: **Web application** (Supabase's server does the
     exchange with Google, not the app). Name: "Versely Supabase".
   - **Authorized redirect URIs** → Add URI:
     `https://ulbpwygzwchsnvdeeife.supabase.co/auth/v1/callback`
     (no JavaScript origins needed).
   - **Create**. Copy the **Client ID** and **Client secret** into your
     password manager.

You don't need an **iOS** OAuth client: that type is only for apps that use
Google's own SDK, and Versely doesn't.

## 2. Supabase dashboard

1. **Authentication** → **Sign In / Providers** → **Google** → turn on
   **Enable Sign in with Google**.
2. **Client IDs**: the Web client ID from step 1.3. **Client Secret
   (for OAuth)**: the client secret. Type or paste them in the dashboard
   yourself. Leave "Skip nonce checks" and "Allow users without an email"
   off. **Save**.
3. **Authentication** → **URL Configuration** → **Redirect URLs** → **Add
   URL** → `versely://auth-callback` → Save. Without it, Supabase sends people
   to the Site URL instead of back to the app.

## 3. Try it

On your iPhone: Settings → Account → **Sign in with Google**. iOS first asks
"Versely Wants to Use 'supabase.co' to Sign In" (the sheet shares Safari's
sign-ins, so someone already signed in to Google there just picks their
account), then Google's account picker. You land back in the app signed in.

Good to know:

- **Same email, same account.** Supabase links a Google sign-in to an
  existing account with the same verified email (email/password or Apple
  with a real address). An Apple account that used **Hide My Email** has a
  different address, so Google creates a separate account there.
- **App Store guideline 4.8** is satisfied: Sign in with Apple is offered
  first, with the same size and shape, wherever Google is.
- **Deleting an account** needs nothing extra for Google: there are no Google
  tokens to revoke (Supabase holds only the identity, which the
  `delete-account` function removes with the account). People can also remove
  Versely at myaccount.google.com → Security → Third-party connections.
- **Privacy**: Google shares the email, name and profile picture link, which
  Supabase keeps with the account. Email Address, Name and User ID are
  already declared (privacy manifest and the App Privacy answers in
  APPLE_SETUP.md); nothing is used for tracking.
- Google's screen says "to continue to ulbpwygzwchsnvdeeife.supabase.co"
  unless you set up a Supabase custom domain (a paid add-on); that's normal.
