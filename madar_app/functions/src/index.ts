import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onRequest } from "firebase-functions/v2/https";

setGlobalOptions({ maxInstances: 10 });

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

/* ------------------------------------------------------------------
   Track Request Push Notification
-------------------------------------------------------------------*/
export const onTrackRequestCreated = onDocumentCreated(
  "trackRequests/{requestId}",
  async (event) => {
    try {
      const data = event.data?.data();
      if (!data) {
        console.log("No data in track request");
        return;
      }

      // Send notification only when the request is created (pending)
      if (data.status !== "pending") {
        console.log("Track request not pending, skipping");
        return;
      }

      const receiverId = data.receiverId;
      if (!receiverId) {
        console.log("No receiverId");
        return;
      }

      // Get FCM tokens of the receiver
      const userDoc = await db.collection("users").doc(receiverId).get();
      if (!userDoc.exists) {
        console.log("Receiver user not found");
        return;
      }

      const tokens: string[] = userDoc.data()?.fcmTokens ?? [];
      if (tokens.length === 0) {
        console.log("No FCM tokens for receiver");
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
        tokens,
      };

      const response = await admin.messaging().sendEachForMulticast(message);

      console.log(
        `Notification sent | success: ${response.successCount}, failure: ${response.failureCount}`
      );

      // Save notification in Firestore (unread)
      await db.collection("notifications").add({
        userId: receiverId,
        type: "track_request",
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

      console.log("Notification document created (unread)");
    } catch (error) {
      console.error("Error sending track request notification:", error);
    }
  }
);

/* ------------------------------------------------------------------
   Unity -> HTTPS Function -> writes to users/{docId}.location
   Purpose: allow Unity to update user location without direct Firestore access
-------------------------------------------------------------------*/
export const setUserLocation = onRequest({ cors: true }, async (req, res) => {
  try {
    if (req.method !== "POST") {
      res.status(405).send("Use POST");
      return;
    }

    const { idToken, userDocId, location } = req.body ?? {};

    if (!idToken) {
      res.status(401).json({ ok: false, error: "Missing idToken" });
      return;
    }

    if (!location?.blenderPosition) {
      res
        .status(400)
        .json({ ok: false, error: "Missing location.blenderPosition" });
      return;
    }

    // Verify Firebase Auth ID token (sent from Flutter via Unity)
    const decoded = await admin.auth().verifyIdToken(idToken);

    // Decide which user document to write to
    let docRef: admin.firestore.DocumentReference | null = null;

    if (typeof userDocId === "string" && userDocId.trim().length > 0) {
      docRef = db.collection("users").doc(userDocId.trim());
    } else if (decoded.email) {
      // Fallback: resolve user document by email
      const snap = await db
        .collection("users")
        .where("email", "==", decoded.email)
        .limit(1)
        .get();

      if (!snap.empty) docRef = snap.docs[0].ref;
    }

    // Last fallback: use uid as document id
    if (!docRef) docRef = db.collection("users").doc(decoded.uid);

    // Write location in the expected shape
    await docRef.set(
      {
        location: {
          blenderPosition: {
            x: location.blenderPosition.x,
            y: location.blenderPosition.y,
            z: location.blenderPosition.z,
            floor: location.blenderPosition.floor ?? "",
          },
          multisetPosition: location.multisetPosition ?? null,
          nearestPOI: location.nearestPOI ?? "Unknown",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );

    res.json({ ok: true, userUid: decoded.uid });
  } catch (e: any) {
    console.error("setUserLocation error:", e);
    res.status(500).json({ ok: false, error: String(e?.message ?? e) });
  }
});
