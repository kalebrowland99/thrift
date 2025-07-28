/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const nodemailer = require("nodemailer");

// Initialize email transporter
const createTransporter = () => {
  // Use environment variables directly
  const email = process.env.GMAIL_EMAIL || "fye.noreply@gmail.com";
  const password = process.env.GMAIL_PASSWORD;
  
  if (!password) {
    throw new Error("Gmail password not configured. Please set GMAIL_PASSWORD environment variable.");
  }
  
  return nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: email,
      pass: password, // Use App Password, not regular password
    },
  });
};

// Email verification function
exports.sendVerificationEmail = onCall(async (request) => {
  const { email, verificationCode, appName } = request.data;
  
  // Validate input
  if (!email || !verificationCode || !appName) {
    throw new HttpsError(
      "invalid-argument",
      "Missing required fields: email, verificationCode, or appName"
    );
  }
  
  // Email validation
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email)) {
    throw new HttpsError(
      "invalid-argument",
      "Invalid email address"
    );
  }
  
  try {
    const transporter = createTransporter();
    
    // Email content
    const mailOptions = {
      from: "\"Fye AI Team\" <fye.noreply@gmail.com>",
      to: email,
      subject: "Your Fye AI Verification Code",
      html: `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Email Verification</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { text-align: center; margin-bottom: 30px; }
            .logo { font-size: 24px; font-weight: bold; color: #000; }
            .code-box { background: #f8f9fa; border: 2px solid #e9ecef; border-radius: 8px; padding: 20px; text-align: center; margin: 20px 0; }
            .code { font-size: 32px; font-weight: bold; letter-spacing: 4px; color: #000; }
            .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #e9ecef; font-size: 14px; color: #666; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <div class="logo">🎵 Fye AI</div>
            </div>
            
            <h2>Email Verification</h2>
            <p>Hello!</p>
            <p>You requested a verification code for your Fye AI account. Enter the code below to continue:</p>
            
            <div class="code-box">
              <div class="code">${verificationCode}</div>
            </div>
            
            <p><strong>This code will expire in 10 minutes.</strong></p>
            <p>If you didn't request this code, you can safely ignore this email.</p>
            
            <div class="footer">
              <p>Best regards,<br>The Fye AI Team</p>
              <p style="font-size: 12px; margin-top: 20px;">
                This is an automated message. Please do not reply to this email.
              </p>
            </div>
          </div>
        </body>
        </html>
      `,
      text: `
Your Fye AI Verification Code

Hello!

You requested a verification code for your Fye AI account. Enter the code below to continue:

${verificationCode}

This code will expire in 10 minutes.

If you didn't request this code, you can safely ignore this email.

Best regards,
The Fye AI Team
      `.trim(),
    };
    
    // Send email
    await transporter.sendMail(mailOptions);
    
    console.log(`✅ Verification email sent successfully to ${email}`);
    return { success: true, message: "Verification email sent successfully" };
    
  } catch (error) {
    console.error("❌ Error sending verification email:", error);
    throw new HttpsError(
      "internal",
      `Failed to send verification email: ${error.message}`
    );
  }
});
