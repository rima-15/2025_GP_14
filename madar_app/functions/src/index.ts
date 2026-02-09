import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
//import { Timestamp } from "firebase-admin/firestore";

setGlobalOptions({ maxInstances: 10 });

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

/* ------------------------------------------------------------------
   Track Request Push Notification (Created)
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

      // Send notification only when created as pending
      if (data.status !== "pending") {
        console.log("Track request not pending, skipping");
        return;
      }

      const receiverId = data.receiverId;
      if (!receiverId) {
        console.log("No receiverId");
        return;
      }

      // Get receiver FCM tokens
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

      // Save notification in Firestore (Unread)
      await db.collection("notifications").add({
        userId: receiverId,
        type: "track_request",
        requiresAction: true, // IMPORTANT: UI can show action buttons
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
   Track Request Push Notification (Accepted / Declined)
-------------------------------------------------------------------*/
export const onTrackRequestStatusChanged = onDocumentUpdated(
  "trackRequests/{requestId}",
  async (event) => {
    try {
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      if (!before || !after) return;

      // Do nothing if status did not change
      if (before.status === after.status) return;

      // Only handle accepted/declined
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
          title: accepted ? "Track Request Accepted" : "Track Request Declined",
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
        requiresAction: false,
        data: {
          requestId: event.params.requestId,
        },
        title: accepted ? "Track Request Accepted" : "Track Request Declined",
        body: accepted
          ? `${after.receiverName} accepted your tracking request`
          : `${after.receiverName} declined your tracking request`,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log("Accept/Decline notification sent");
    } catch (e) {
      console.error("Error:", e);
    }
  }
);
/* ------------------------------------------------------------------
   🔔 Track Started Notification (Scheduled)
-------------------------------------------------------------------*/
export const onTrackStarted = onSchedule("every 1 minutes", async () => {
  const now = admin.firestore.Timestamp.now();

  const snap = await db
    .collection("trackRequests")
    .where("status", "==", "accepted")
    .where("startAt", "<=", now)
    .get();

  if (snap.empty) return;

  const batch = db.batch();

  for (const doc of snap.docs) {
    const data = doc.data();
    const requestId = doc.id;

    const senderId = data.senderId;
    const receiverId = data.receiverId;

    if (!senderId || !receiverId) continue;

    const notifiedUsers: string[] = data.startNotifiedUsers || [];

    if (notifiedUsers.includes(receiverId)) continue;

    // ================= RECEIVER PUSH =================
    const receiverDoc = await db.collection("users").doc(receiverId).get();
    const receiverTokens: string[] = receiverDoc.data()?.fcmTokens ?? [];

    if (receiverTokens.length > 0) {
      await admin.messaging().sendEachForMulticast({
        notification: {
          title: "Tracking Started",
          body: `${data.senderName} can now track your location`,
        },
        data: {
          type: "trackStarted",
          requestId,
        },
        tokens: receiverTokens,
      });
    }

    // ================= SENDER PUSH (مرة وحدة) =================
    if (notifiedUsers.length === 0) {
      const senderDoc = await db.collection("users").doc(senderId).get();
      const senderTokens: string[] = senderDoc.data()?.fcmTokens ?? [];

      if (senderTokens.length > 0) {
        await admin.messaging().sendEachForMulticast({
          notification: {
            title: "Tracking Started",
            body: "You can now track your friends",
          },
          data: {
            type: "trackStarted",
            requestId,
          },
          tokens: senderTokens,
        });
      }
    }

    // ================= FIRESTORE NOTIFICATIONS =================

    batch.set(db.collection("notifications").doc(), {
      userId: receiverId,
      type: "trackStarted",
      requiresAction: true,
      isRead: false,
      title: "Tracking Started",
      body: `${data.senderName} can now track your location`,
      data: {
        requestId,
        endAt: data.endAt,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (notifiedUsers.length === 0) {
      batch.set(db.collection("notifications").doc(), {
        userId: senderId,
        type: "trackStarted",
        requiresAction: false,
        isRead: false,
        title: "Tracking Started",
        body: "You can now track your friends",
        data: {
          requestId,
          endAt: data.endAt,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    batch.update(doc.ref, {
      startNotifiedUsers: admin.firestore.FieldValue.arrayUnion(receiverId),
    });
  }

  await batch.commit();
});



/* ------------------------------------------------------------------
   Unity Location Writer (HTTPS)
   Unity -> POST -> Cloud Function -> writes to users/{docId}.location
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
      res.status(400).json({ ok: false, error: "Missing location.blenderPosition" });
      return;
    }

    // Verify Firebase Auth ID token
    const decoded = await admin.auth().verifyIdToken(idToken);

    // Decide which users doc to write
    let docRef: FirebaseFirestore.DocumentReference | null = null;

    if (typeof userDocId === "string" && userDocId.trim().length > 0) {
      docRef = db.collection("users").doc(userDocId.trim());
    } else if (decoded.email) {
      // Fallback: resolve by email (same logic as Flutter)
      const snap = await db
        .collection("users")
        .where("email", "==", decoded.email)
        .limit(1)
        .get();
      if (!snap.empty) docRef = snap.docs[0].ref;
    }

    // Last fallback: uid doc
    if (!docRef) docRef = db.collection("users").doc(decoded.uid);

    // Write location in the exact shape your Flutter reads
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
