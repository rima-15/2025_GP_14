import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

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
    } catch (error) {
      console.error("🔥 Error sending track request notification:", error);
    }
  }
);
