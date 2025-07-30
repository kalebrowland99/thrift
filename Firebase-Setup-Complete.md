# 🔥 Complete Firebase Setup Guide for Thrifty Email Verification

## Current Status ✅
- ✅ Firebase project: `thrift-882cb` (active)
- ✅ Firebase CLI installed and logged in
- ✅ Cloud Functions deployed: `sendVerificationEmail`
- ✅ iOS app configured with `GoogleService-Info.plist`
- ✅ Firebase SDK integrated in iOS app

## 🚨 Required Setup Steps

### 1. Email Configuration (CRITICAL)

Your Firebase function is deployed but needs email credentials to work. You have two options:

#### Option A: Gmail (Recommended for testing)
1. Create a Gmail account for your app (e.g., `thrifty.noreply@gmail.com`)
2. Enable 2-factor authentication
3. Generate an App Password:
   - Go to Google Account settings
   - Security → 2-Step Verification → App passwords
   - Generate password for "Mail"
4. Set environment variables:

```bash
# Set Gmail credentials
firebase functions:secrets:set GMAIL_EMAIL "thrifty.noreply@gmail.com"
firebase functions:secrets:set GMAIL_PASSWORD "your-16-character-app-password"
```

#### Option B: SendGrid (Production recommended)
1. Sign up for SendGrid (free tier: 100 emails/day)
2. Verify your domain
3. Create API key
4. Set environment variables:

```bash
firebase functions:secrets:set SENDGRID_API_KEY "your-sendgrid-api-key"
```

### 2. Update Firebase Function (if using SendGrid)

If you choose SendGrid, update `functions/index.js`:

```javascript
// Replace the createTransporter function
const createTransporter = () => {
  const apiKey = process.env.SENDGRID_API_KEY;
  
  if (!apiKey) {
    throw new Error("SendGrid API key not configured");
  }
  
  return nodemailer.createTransport({
    host: 'smtp.sendgrid.net',
    port: 587,
    secure: false,
    auth: {
      user: 'apikey',
      pass: apiKey
    }
  });
};
```

### 3. Deploy Updated Function

```bash
cd functions
npm install
firebase deploy --only functions
```

### 4. Test Email Verification

1. Run your iOS app
2. Try email sign-in with a real email address
3. Check Firebase Functions logs:

```bash
firebase functions:log --only sendVerificationEmail
```

## 🔧 Development Testing

For development, your app has a fallback mode:
- If Firebase function fails, it logs the verification code to console
- Use `apple@test.com` with code `1234` for testing

## 📱 iOS App Configuration

Your iOS app is already properly configured:

### Firebase SDK Integration ✅
```swift
// ThriftyApp.swift
func configureFirebase() {
    FirebaseApp.configure()
    print("✅ Firebase configured successfully")
}
```

### Email Verification Flow ✅
- Two-screen flow: Email entry → Code verification
- 4-digit code input with auto-advance
- 10-minute expiration
- Resend functionality
- Error handling

### Authentication Manager ✅
- Handles Firebase Auth integration
- Creates user accounts with random passwords
- Manages verification state
- Handles both new users and existing users

## 🚀 Production Checklist

Before going live:

1. **Email Provider**: Set up SendGrid or Gmail with proper credentials
2. **Domain Verification**: Verify your sending domain
3. **Rate Limiting**: Implement rate limiting for verification requests
4. **Error Monitoring**: Set up Firebase Crashlytics
5. **Analytics**: Enable Firebase Analytics
6. **Security Rules**: Review Firestore security rules

## 🔍 Troubleshooting

### Common Issues:

1. **"Gmail password not configured"**
   - Set GMAIL_PASSWORD environment variable
   - Use App Password, not regular password

2. **"Failed to send verification email"**
   - Check Firebase Functions logs
   - Verify email credentials
   - Check Gmail/SendGrid quotas

3. **iOS app can't connect to Firebase**
   - Verify `GoogleService-Info.plist` is in the app bundle
   - Check Firebase project settings
   - Ensure iOS bundle ID matches

### Debug Commands:

```bash
# Check function status
firebase functions:list

# View function logs
firebase functions:log --only sendVerificationEmail

# Test function locally
firebase emulators:start --only functions

# Check environment variables
firebase functions:secrets:get
```

## 📞 Support

If you encounter issues:
1. Check Firebase Console: https://console.firebase.google.com/project/thrift-882cb
2. Review function logs: `firebase functions:log`
3. Test with development fallback mode first

---

**Next Steps:**
1. Set up email credentials (Gmail or SendGrid)
2. Deploy updated function
3. Test with real email addresses
4. Monitor logs for any issues 