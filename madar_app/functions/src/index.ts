import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";


setGlobalOptions({ maxInstances: 10 });

// 🔥 Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

/* ------------------------------------------------------------------
   🔔 Track Request Push Notification
-------------------------------------------------------------------*/
export const onTrackRequestCreated = onDocumentCreated(
  "trackRequests/{requestId}",
  async (event) => {
    try {
      const data = event.data?.data();
      if (!data) {
        console.log("❌ No data in track request");
        return;
      }

      // نرسل الإشعار فقط عند إنشاء الطلب
      if (data.status !== "pending") {
        console.log("ℹ️ Track request not pending, skipping");
        return;
      }

      const receiverId = data.receiverId;
      if (!receiverId) {
        console.log("❌ No receiverId");
        return;
      }

      // جلب FCM Tokens للمستقبل
      const userDoc = await db.collection("users").doc(receiverId).get();
      if (!userDoc.exists) {
        console.log("❌ Receiver user not found");
        return;
      }

      const tokens: string[] = userDoc.data()?.fcmTokens ?? [];
      if (tokens.length === 0) {
        console.log("❌ No FCM tokens for receiver");
        return;
      }

      const message = {
        notification: {
          title: "New Track Request",
          body: `${data.senderName} wants to track your location`,
        },
        data: {
          type: "trackRequest",
          requestId: event.params.requestId,
        },
        tokens: tokens,
      };

      const response = await admin.messaging().sendEachForMulticast(message);

      console.log(
        `🔔 Notification sent | success: ${response.successCount}, failure: ${response.failureCount}`
      );
      // 🔔 Save notification in Firestore (Unread)
await db.collection("notifications").add({
  userId: receiverId,
  type: "track_request",

  requiresAction: true, // 🔥 هذا المفتاح المهم

  title: "New Track Request",
  body: `${data.senderName} wants to track your location`,

  data: {
    requestId: event.params.requestId,
    senderId: data.senderId,
    venueId: data.venueId ?? null,
  },

  isRead: false,
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
});


console.log("📦 Notification document created (unread)");

    } catch (error) {
      console.error("🔥 Error sending track request notification:", error);
    }
  }
);
/* ------------------------------------------------------------------
   🔔 Track Request Accepted / Declined
-------------------------------------------------------------------*/
export const onTrackRequestStatusChanged = onDocumentUpdated(
  "trackRequests/{requestId}",
  async (event) => {
    try {
      const before = event.data?.before.data();
      const after = event.data?.after.data();

      if (!before || !after) return;

      // لا نسوي شيء إذا الحالة ما تغيرت
      if (before.status === after.status) return;

      if (after.status !== "accepted" && after.status !== "declined") return;

      const senderId = after.senderId;
      if (!senderId) return;

      const senderDoc = await db.collection("users").doc(senderId).get();
      if (!senderDoc.exists) return;

      const tokens: string[] = senderDoc.data()?.fcmTokens ?? [];
      if (tokens.length === 0) return;

      const accepted = after.status === "accepted";

      const message = {
        notification: {
          title: accepted
            ? "Track Request Accepted"
            : "Track Request Declined",
          body: accepted
            ? `${after.receiverName} accepted your tracking request`
            : `${after.receiverName} declined your tracking request`,
        },
        data: {
          type: accepted ? "trackAccepted" : "trackDeclined",
          requestId: event.params.requestId,
        },
        tokens,
      };

      await admin.messaging().sendEachForMulticast(message);

     await db.collection("notifications").add({
  userId: senderId,
  type: accepted ? "trackAccepted" : "trackRejected",
  requiresAction:false,


  data: {
    requestId: event.params.requestId,   // ⭐ هذا المهم
  },

  title: accepted
    ? "Track Request Accepted"
    : "Track Request Declined",

  body: accepted
    ? `${after.receiverName} accepted your tracking request`
    : `${after.receiverName} declined your tracking request`,

  isRead: false,
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
});


      console.log("✅ Accept / Decline notification sent");

    } catch (e) {
      console.error("🔥 Error:", e);
    }
  }
);
