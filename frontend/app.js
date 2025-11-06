// API Configuration - reads from config.js which can be set via environment variable
let API_BASE_URL = window.API_BASE_URL || 'http://localhost:3000/api/v1';

// Update API URL from input
function updateApiUrl() {
    const input = document.getElementById('apiUrl');
    API_BASE_URL = input.value.trim() || 'http://localhost:3000/api/v1';
    loadStudents();
}

// Load all students
async function loadStudents() {
    const loading = document.getElementById('loading');
    const error = document.getElementById('error');
    const studentsList = document.getElementById('students-list');
    
    loading.style.display = 'block';
    error.style.display = 'none';
    studentsList.innerHTML = '';

    try {
        const response = await fetch(`${API_BASE_URL}/students`);
        
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        const data = await response.json();
        displayStudents(data.students || []);
    } catch (err) {
        console.error('API Error:', err);
        const errorMsg = err.message.includes('Failed to fetch') || err.message.includes('NetworkError') 
            ? `Cannot connect to API at ${API_BASE_URL}. Check if the backend is running and accessible.`
            : `Error loading students: ${err.message}. API URL: ${API_BASE_URL}`;
        error.textContent = errorMsg;
        error.style.display = 'block';
        studentsList.innerHTML = '';
    } finally {
        loading.style.display = 'none';
    }
}

// Display students in the UI
function displayStudents(students) {
    const studentsList = document.getElementById('students-list');
    
    if (students.length === 0) {
        studentsList.innerHTML = `
            <div class="empty-state">
                <h3>No students found</h3>
                <p>Add your first student using the form above!</p>
            </div>
        `;
        return;
    }

    studentsList.innerHTML = students.map(student => `
        <div class="student-card">
            <h3>${escapeHtml(student.name)}</h3>
            <p><strong>Email:</strong> ${escapeHtml(student.email)}</p>
            <p><strong>ID:</strong> ${student.id}</p>
            <div class="student-actions">
                <button class="btn-edit" onclick="editStudent(${student.id}, '${escapeHtml(student.name)}', '${escapeHtml(student.email)}')">
                    ✏️ Edit
                </button>
                <button class="btn-delete" onclick="deleteStudent(${student.id})">
                    🗑️ Delete
                </button>
            </div>
        </div>
    `).join('');
}

// Handle form submission
document.getElementById('student-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const studentId = document.getElementById('student-id').value;
    const name = document.getElementById('name').value.trim();
    const email = document.getElementById('email').value.trim();
    
    if (!name || !email) {
        alert('Please fill in all fields');
        return;
    }

    const submitBtn = document.getElementById('submit-btn');
    const originalText = submitBtn.textContent;
    submitBtn.textContent = 'Processing...';
    submitBtn.disabled = true;

    try {
        let response;
        if (studentId) {
            // Update existing student
            response = await fetch(`${API_BASE_URL}/students/${studentId}`, {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ name, email }),
            });
        } else {
            // Create new student
            response = await fetch(`${API_BASE_URL}/students`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ name, email }),
            });
        }

        if (!response.ok) {
            const errorData = await response.json().catch(() => ({}));
            throw new Error(errorData.message || `HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        alert(studentId ? 'Student updated successfully!' : 'Student created successfully!');
        resetForm();
        loadStudents();
    } catch (err) {
        console.error('Form submission error:', err);
        const errorMsg = err.message.includes('Failed to fetch') || err.message.includes('NetworkError')
            ? 'Cannot connect to API. Check if the backend is running and accessible. If using HTTPS with a self-signed certificate, you may need to accept the certificate in your browser.'
            : `Error: ${err.message}`;
        alert(errorMsg);
    } finally {
        submitBtn.textContent = originalText;
        submitBtn.disabled = false;
    }
});

// Edit student
function editStudent(id, name, email) {
    document.getElementById('student-id').value = id;
    document.getElementById('name').value = name;
    document.getElementById('email').value = email;
    document.getElementById('form-title').textContent = 'Edit Student';
    document.getElementById('submit-btn').textContent = 'Update Student';
    document.getElementById('cancel-btn').style.display = 'inline-block';
    
    // Scroll to form
    document.querySelector('.form-section').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

// Delete student
async function deleteStudent(id) {
    if (!confirm('Are you sure you want to delete this student?')) {
        return;
    }

    try {
        const response = await fetch(`${API_BASE_URL}/students/${id}`, {
            method: 'DELETE',
        });

        if (!response.ok) {
            const errorData = await response.json().catch(() => ({}));
            throw new Error(errorData.message || `HTTP error! status: ${response.status}`);
        }

        alert('Student deleted successfully!');
        loadStudents();
    } catch (err) {
        alert(`Error: ${err.message}`);
    }
}

// Reset form
function resetForm() {
    document.getElementById('student-form').reset();
    document.getElementById('student-id').value = '';
    document.getElementById('form-title').textContent = 'Add New Student';
    document.getElementById('submit-btn').textContent = 'Add Student';
    document.getElementById('cancel-btn').style.display = 'none';
}

// Escape HTML to prevent XSS
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Load students on page load
document.addEventListener('DOMContentLoaded', () => {
    // Initialize API URL input with current value
    document.getElementById('apiUrl').value = API_BASE_URL;
    loadStudents();
});

