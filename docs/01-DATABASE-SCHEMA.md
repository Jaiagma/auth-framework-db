# Database Schema Documentation

## Overview
This document outlines the database schema for the Auth Framework Database.

## Tables

### Users
- **user_id** (INT, Primary Key, Auto-increment) - Unique identifier for each user.
- **username** (VARCHAR) - The username of the user.
- **email** (VARCHAR) - The user's email address.
- **password_hash** (VARCHAR) - Hashed password for the user.
- **created_at** (DATETIME) - Timestamp when the user was created.

### Roles
- **role_id** (INT, Primary Key, Auto-increment) - Unique identifier for each role.
- **role_name** (VARCHAR) - The name of the role (e.g., Admin, User).

### UserRoles
- **user_role_id** (INT, Primary Key, Auto-increment) - Unique identifier for the user role relationship.
- **user_id** (INT, Foreign Key) - Reference to the Users table.
- **role_id** (INT, Foreign Key) - Reference to the Roles table.

### Sessions
- **session_id** (INT, Primary Key, Auto-increment) - Unique identifier for each session.
- **user_id** (INT, Foreign Key) - Reference to the Users table.
- **session_token** (VARCHAR) - Token used for session authentication.
- **created_at** (DATETIME) - Timestamp when the session was created.
- **expires_at** (DATETIME) - Timestamp when the session expires.

## Relationships
- A user can have multiple roles (many-to-many relationship).
- A role can be assigned to multiple users.

## Implementation Details
- The database uses **InnoDB** for transaction support.
- Foreign keys enforce referential integrity between tables.

## ER Diagram
(Add an ER diagram image here if available)

## Additional Notes
Make sure to regularly backup the database and follow security best practices to protect user data.