# Student Management Frontend

A simple, modern web interface for managing students using the Student API backend.

## Features

- ✅ View all students
- ✅ Add new students
- ✅ Edit existing students
- ✅ Delete students
- ✅ Configurable API URL
- ✅ Responsive design

## How to Use

1. **Configure the API URL** (if needed):
   ```bash
   cd frontend
   REACT_APP_API_URL=http://localhost:3000/api/v1 node generate-config.js
   ```

2. **Start the backend API** (make sure it's running on port 3000 or your configured port)

3. **Open the frontend**:
   - Simply open `frontend/index.html` in your web browser, or
   - Serve it with a simple HTTP server:
     ```bash
     cd frontend
     python3 -m http.server 8080
     ```
     Then open `http://localhost:8080` in your browser.

## Docker Deployment

### Building the Docker Image

```bash
cd frontend

# Build with default API URL
./build-docker.sh

# Or build with custom API URL
API_BASE_URL=https://student-api.atlan.com/api/v1 ./build-docker.sh

# Or build with custom tag
./build-docker.sh v1.0.0
```

### Running the Container

```bash
# Run locally (frontend runs on port 8080 inside container, mapped to 8081 on host)
docker run -p 8081:8080 akshat5302/student-crud-frontend:latest

# Or with custom API URL
docker run -p 8081:8080 \
  -e API_BASE_URL=http://student-api.atlan.com/api/v1 \
  akshat5302/student-crud-frontend:latest
```

Then access at `http://localhost:8081`

### Pushing to Registry

```bash
docker push akshat5302/student-crud-frontend:latest
docker push akshat5302/student-crud-frontend:v1.0.0
```

## Configuration

### Setting the Backend URL

The backend URL is configured via environment variable during Docker build:

```bash
# During build
API_BASE_URL=http://student-api.atlan.com/api/v1 ./build-docker.sh

# Or at runtime
docker run -e API_BASE_URL=http://student-api.atlan.com/api/v1 ...
```

For local development without Docker:
```bash
cd frontend
REACT_APP_API_URL=http://localhost:3000/api/v1 node generate-config.js
```

**Note:** You can also change the API URL temporarily in the browser using the "API Base URL" input field at the top of the page, but this will reset on page reload.

## API Endpoints Used

The frontend uses the following endpoints:
- `GET /api/v1/students` - Get all students
- `GET /api/v1/students/:id` - Get a specific student (not used in UI, but available)
- `POST /api/v1/students` - Create a new student
- `PUT /api/v1/students/:id` - Update a student
- `DELETE /api/v1/students/:id` - Delete a student

## Browser Compatibility

Works in all modern browsers (Chrome, Firefox, Safari, Edge).

