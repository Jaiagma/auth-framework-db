# API Endpoints Documentation

This document contains comprehensive details about the API endpoints available in the project.

## Base URL

`https://api.example.com/v1`

## Endpoints

### 1. Authentication

- **Endpoint:** `/auth/login`  
  - **Method:** POST  
  - **Request Body:**
    ```json
    { 
        "username": "string", 
        "password": "string" 
    }
    ```
  - **Response:**
    - **200 OK**: 
      ```json
      {
          "token": "string"
      }
      ```
    - **401 Unauthorized**: 
      ```json
      {
          "error": "Invalid credentials"
      }
      ```

### 2. Get User Profile

- **Endpoint:** `/users/profile`  
  - **Method:** GET  
  - **Request Headers:**
    - `Authorization: Bearer {token}`
  - **Response:**
    - **200 OK**:
      ```json
      {
          "id": "string",
          "username": "string",
          "email": "string"
      }
      ```
    - **401 Unauthorized**: 
      ```json
      {
          "error": "Token required"
      }
      ```

### 3. Update User Profile

- **Endpoint:** `/users/profile`  
  - **Method:** PUT  
  - **Request Headers:**
    - `Authorization: Bearer {token}`
  - **Request Body:**
    ```json
    {
        "email": "string"
    }
    ```
  - **Response:**  
    - **200 OK**:
      ```json
      {
          "message": "Profile updated successfully"
      }
      ```
    - **400 Bad Request**: 
      ```json
      {
          "error": "Invalid email format"
      }
      ```

### Error Handling

All API responses follow a JSON format. Error responses will always include an error message and relevant status code. 

- **400 Bad Request**: Indicates that the request was invalid.  
- **401 Unauthorized**: Indicates that authentication has failed.  
- **403 Forbidden**: Indicates that the user does not have permission to access the resource.  
- **404 Not Found**: Indicates that the specified resource was not found.  
- **500 Internal Server Error**: Indicates that an unexpected error has occurred on the server.

---

For more information, refer to the API documentation and code comments in the repository.