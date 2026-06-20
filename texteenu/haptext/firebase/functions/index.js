const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");

initializeApp();

const DISPLAY_NAMES = {
  ameena: "Ameena",
  gonzalo: "Gonzalo",
};

const IOS_BUNDLE_ID = "com.loveyourhaptics.app.haptext";

function redactedToken(token) {
  if (typeof token !== "string" || token.length < 14) {
    return "invalid-token";
  }

  return `${token.slice(0, 8)}...${token.slice(-6)}`;
}

exports.sendHapTextMessagePush = onDocumentCreated(
  "haptext_chats/{chatId}/messages/{messageId}",
  async (event) => {
    const message = event.data?.data();

    if (!message || message.historyVersion !== 2 || message.isVisibleToReceiver === false) {
      return;
    }

    const senderID = message.senderID;
    const recipientID = message.recipientID;

    if (!DISPLAY_NAMES[senderID] || !DISPLAY_NAMES[recipientID] || senderID === recipientID) {
      return;
    }

    const snapshot = await getFirestore()
      .collection("haptext_users")
      .doc(recipientID)
      .collection("notification_tokens")
      .where("notificationsEnabled", "==", true)
      .get();

    const senderPushToken = message.senderPushToken || "";
    const tokens = snapshot.docs
      .map((doc) => doc.get("token"))
      .filter((token) => typeof token === "string" && token.length > 0 && token !== senderPushToken);

    if (tokens.length === 0) {
      console.log("HapText push skipped: no recipient tokens", {
        chatId: event.params.chatId,
        messageId: event.params.messageId,
        senderID,
        recipientID,
        registeredTokenDocs: snapshot.size,
      });
      return;
    }

    const isAudio = message.type === "audio";
    const body = isAudio ? "Audio message" : String(message.text || "");
    const title = DISPLAY_NAMES[senderID];

    console.log("HapText push sending", {
      chatId: event.params.chatId,
      messageId: event.params.messageId,
      senderID,
      recipientID,
      tokenCount: tokens.length,
    });

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title,
        body,
      },
      apns: {
        headers: {
          "apns-topic": IOS_BUNDLE_ID,
          "apns-push-type": "alert",
          "apns-priority": "10",
        },
        payload: {
          aps: {
            sound: "default",
            threadId: event.params.chatId,
            category: "HAPTEXT_MESSAGE",
            interruptionLevel: "active",
          },
        },
      },
      data: {
        chatId: event.params.chatId,
        messageId: event.params.messageId,
        senderId: senderID,
        recipientId: recipientID,
      },
    });

    const staleTokens = [];
    response.responses.forEach((sendResponse, index) => {
      if (!sendResponse.success) {
        const code = sendResponse.error?.code || "";
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          staleTokens.push(tokens[index]);
        } else {
          console.error("HapText push failed", {
            code,
            message: sendResponse.error?.message,
            token: redactedToken(tokens[index]),
            chatId: event.params.chatId,
            messageId: event.params.messageId,
            recipientID,
          });
        }
      }
    });

    console.log("HapText push result", {
      chatId: event.params.chatId,
      messageId: event.params.messageId,
      successCount: response.successCount,
      failureCount: response.failureCount,
      staleTokenCount: staleTokens.length,
    });

    await Promise.all(
      staleTokens.map(async (token) => {
        const tokenDoc = snapshot.docs.find((doc) => doc.get("token") === token);
        if (tokenDoc) {
          await tokenDoc.ref.delete();
        }
      })
    );
  }
);
