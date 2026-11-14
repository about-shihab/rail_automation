# Bangladesh Railway ("Rail Sheba") Official API Documentation

Comprehensive API documentation for the Bangladesh Railway (*Rail Sheba*) mobile application (`com.shohoz.dtrainpwa`).

---

## 1. Architecture Overview & Base Gateway

The Bangladesh Railway e-ticketing ecosystem is managed by Shohoz. The mobile application operates via a single-page web app container communicating with a REST API gateway alongside Cloudflare security validation.

- **App API Base URL:** `https://railspaapi.shohoz.com/v1.0/app`
- **Web API Base URL:** `https://railspaapi.shohoz.com/v1.0/web`
- **Websocket Server:** `https://train-websocket.shohoz.com/`
- **Allowed Hosts:** `railspaapi.shohoz.com`, `railapp.railway.gov.bd`, `eticket.railway.gov.bd`

### Standard Request Headers
```http
Content-Type: application/json
Accept: application/json, text/plain, */*
Origin: https://eticket.railway.gov.bd
Referer: https://eticket.railway.gov.bd/
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36
X-Requested-With: XMLHttpRequest
```

### Authenticated Request Headers
```http
Authorization: Bearer <JWT_ACCESS_TOKEN>
X-Device-Id: <DEVICE_UUID_OR_FINGERPRINT>
X-Device-Key: <DEVICE_KEY>
X-Action-Token: <ACTION_TOKEN>
```
*Query Parameters injected by mobile HTTP interceptor:*
`android_app_version=11&android_device_id=2`

---

## 2. Authentication & Account APIs

### 2.1 Sign In (Login)
* **Method:** `POST`
* **Path:** `/auth/sign-in`
* **Headers:** Standard Headers
* **Body:**
```json
{
  "mobile_number": "017XXXXXXXX",
  "password": "UserPassword",
  "cft_response": "<TURNSTILE_TOKEN>"
}
```
* **Success Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "token": "eyJhbGciOi...",
    "user": {
      "user_id": 123456,
      "mobile_number": "017XXXXXXXX",
      "email": "user@example.com",
      "full_name": "Rahim Ahmed",
      "nid": "1234567890",
      "post_code": "1205"
    },
    "device_key": "ssdk_xxxx"
  }
}
```

### 2.2 Sign Out (Logout)
* **Method:** `POST`
* **Path:** `/auth/sign-out`
* **Headers:** `Authorization: Bearer <TOKEN>`

### 2.3 User Profile
* **Method:** `GET` / `POST`
* **Path:** `/auth/profile`
* **Headers:** `Authorization: Bearer <TOKEN>`

### 2.4 Forgot Password Flow
1. **Send OTP:** `POST /auth/password/forgot`  
   Body: `{"mobile_number": "017XXXXXXXX"}`
2. **Verify OTP:** `POST /auth/password/verify-otp`  
   Body: `{"mobile_number": "017XXXXXXXX", "otp": "123456"}`
3. **Reset Password:** `POST /auth/password/reset`  
   Body: `{"mobile_number": "017XXXXXXXX", "password": "NewPassword", "otp": "123456"}`

---

## 3. Search & Train Schedules

### 3.1 Search Trips
* **Method:** `GET`
* **Path:** `/bookings/search-trips-v2`
* **Query Parameters:**
  - `from_city`: Station name (e.g. `Dhaka`)
  - `to_city`: Station name (e.g. `Chattogram`)
  - `date_of_journey`: Journey date in `DD-Mon-YYYY` (e.g. `25-Nov-2026`)
  - `seat_class`: `ALL` or specific class (`S_CHAIR`, `SNIGDHA`, `AC_B`, `AC_S`, `F_SEAT`, `SHOVAN`)
* **Success Response (200 OK):**
```json
{
  "data": {
    "trains": [
      {
        "trip_number": "SUBORNO EXPRESS (702)",
        "departure_date_time": "25 Nov, 04:30 pm",
        "arrival_date_time": "25 Nov, 09:50 pm",
        "travel_time": "05h 20m",
        "origin_city_name": "dhaka",
        "destination_city_name": "chattogram",
        "seat_types": [
          {
            "key": 7,
            "type": "SNIGDHA",
            "trip_id": 8606141,
            "trip_route_id": 1234,
            "fare": "750.00",
            "vat": "112.50",
            "seats_available": 45
          }
        ]
      }
    ]
  }
}
```

### 3.2 Train Route & Halts
* **Method:** `GET`
* **Path:** `/train-routes`
* **Query Parameters:** `trip_id` or `train_id`

### 3.3 All Trains Info
* **Method:** `GET`
* **Path:** `/all-trains/info`

---

## 4. Seat Layout & Reservation Workflow

### 4.1 Seat Layout
Fetches coach layouts, available seats, and seat IDs.
* **Method:** `GET`
* **Path:** `/bookings/seat-layout`
* **Query Parameters:**
  - `trip_id`: Numeric trip identifier
  - `trip_route_id`: Route identifier
  - `cft_response`: Turnstile verification token (when required)
* **Headers:** Standard Headers + `Authorization: Bearer <TOKEN>`

### 4.2 Reserve Seat (Hold Seat)
Locks the selected seats for 5 minutes during checkout.
* **Method:** `PATCH`
* **Path:** `/bookings/reserve-seat`
* **Headers:** `Authorization: Bearer <TOKEN>`, `X-Action-Token`
* **Body:**
```json
{
  "ticket_id": 860614101,
  "route_id": 1234,
  "extras": {
    "seat_number": "KA-12",
    "trip_number": "702",
    "origin_name": "Dhaka",
    "destination_name": "Chattogram"
  }
}
```
* **Response Header Captured:** `X-Action-Token` (used for subsequent requests)
* **Response Body:** `{"ack": 1, "data": { ... }}`

### 4.3 Release Seat (Unhold)
* **Single Release:** `PATCH /bookings/release-seat`
* **Bulk Release:** `PATCH /bookings/bulk-release-seat`
* **Body:**
```json
{
  "ticket_id": 860614101,
  "route_id": 1234
}
```

---

## 5. Passenger Details, OTP & Payment

### 5.1 Submit Passenger Details
* **Method:** `POST`
* **Path:** `/bookings/passenger-details`
* **Headers:** `Authorization: Bearer <TOKEN>`
* **Body:**
```json
{
  "trip_id": 8606141,
  "trip_route_id": 1234,
  "tickets": [860614101],
  "passengers": [
    {
      "name": "Rahim Ahmed",
      "passenger_type": "ADULT",
      "gender": "male",
      "seat_number": "KA-12",
      "mobile_number": "017XXXXXXXX"
    }
  ]
}
```
* **Response:** `{"success": true, "senior_citizen_eligible": false}`

### 5.2 Booking OTP Verification
* **Resend OTP:** `POST /bookings/resend-otp`
* **Verify OTP:** `POST /bookings/verify-otp`
* **Body:**
```json
{
  "trip_id": 8606141,
  "trip_route_id": 1234,
  "otp": "123456"
}
```

### 5.3 Payment Confirmation
* **Method:** `POST`
* **Path:** `/bookings/confirm-payment`
* Directs user to the payment gateway (bKash / Nagad / Debit / Credit card).

---

## 6. Tickets, History & Verification

### 6.1 Upcoming & Past Trips
* **Upcoming Trips:** `GET /trips/upcoming-v2`
* **Past Trips:** `GET /trips/past-v2`
* **Trip Details:** `GET /trips-v2?order_id=<ORDER_ID>`

### 6.2 Ticket Verification
* **Method:** `POST`
* **Path:** `/trips/verify-ticket`
* **Body:**
```json
{
  "ticket_id": "ABC123XYZ",
  "mobile_number": "017XXXXXXXX"
}
```

### 6.3 Ticket PDF Download
* **Method:** `GET`
* **Path:** `/trips/download-ticket/{order_id}`
* **Headers:** `Authorization: Bearer <TOKEN>`
* **Response Content-Type:** `application/pdf`

---

## 7. Refunds

* **Calculate Refund:** `POST /bookings/refund-calculation`  
  Body: `{"ticket_id": "ABC123XYZ"}`
* **Request Refund:** `POST /bookings/refund-request`  
  Body: `{"ticket_id": "ABC123XYZ", "reason": "Travel plan cancelled"}`
* **Verify Refund OTP:** `POST /bookings/refund-request-otp`  
  Body: `{"ticket_id": "ABC123XYZ", "otp": "123456"}`

---

## 8. Security & Cloudflare Turnstile Reference

Bangladesh Railway enforces Cloudflare Turnstile token validation on critical endpoints:
- **Interactive Site Key:** `0x4AAAAAAB5VTjZ90pUxRuXR`
- **Invisible Site Key:** `0x4AAAAAACNkZ_TxQr_zpcZW`
- **reCAPTCHA v2 Fallback Site Key:** `6LcufsUhAAAAADFOLSJnrKI0XP_8JKaIuEi7kCMI`

Turnstile tokens (`cft_response`) are single-use cryptographically signed tokens generated client-side via JavaScript challenges.
