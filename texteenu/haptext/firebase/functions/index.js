const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");

initializeApp();

const DISPLAY_NAMES = {
  ameena: "Ameena",
  gonzalo: "Gonzalo",
};

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
      return;
    }

    const isAudio = message.type === "audio";
    const body = isAudio ? "Audio message" : String(message.text || "");
    const title = DISPLAY_NAMES[senderID];

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title,
        body,
      },
      apns: {
        headers: {
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
          console.error("HapText push failed", code, sendResponse.error?.message);
        }
      }
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
