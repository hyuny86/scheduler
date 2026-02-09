document.addEventListener('DOMContentLoaded', () => {
    const tableBody = document.getElementById('scheduleBody');
    const headerRow = document.getElementById('headerRow');
    const monthInput = document.getElementById('scheduleMonth');
    const addEmployeeBtn = document.getElementById('addEmployeeBtn');

    // Set current month
    const now = new Date();
    monthInput.value = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

    let employees = [];
    const urlParams = new URLSearchParams(window.location.search);
    const isViewer = urlParams.get('mode') === 'view';

    if (isViewer) {
        document.body.classList.add('viewer-mode');
        document.getElementById('addEmployeeBtn').style.display = 'none';
        document.getElementById('autoAssignBtn').style.display = 'none';
        document.getElementById('saveBtn').style.display = 'none';
        document.querySelector('h1').innerText = "📅 근무 스케줄 현황 (보기 전용)";
    }

    // --- Initialization ---

    function getDaysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate();
    }

    function renderHeader(year, month) {
        // Clear existing header cells except the first one
        while (headerRow.children.length > 1) {
            headerRow.removeChild(headerRow.lastChild);
        }

        const days = getDaysInMonth(year, month);
        for (let i = 1; i <= days; i++) {
            const th = document.createElement('th');
            const date = new Date(year, month, i);
            const dayName = date.toLocaleDateString('ko-KR', { weekday: 'short' });
            th.innerText = `${i}\n(${dayName})`;

            // Highlight weekends
            if (date.getDay() === 0) th.style.color = 'red';
            if (date.getDay() === 6) th.style.color = 'blue';

            headerRow.appendChild(th);
        }
    }

    function renderGrid() {
        // Fetch employees and schedules first (mock for now or real fetch)
        fetchEmployees().then(data => {
            employees = data;
            drawRows();
        });
    }

    async function fetchEmployees() {
        const res = await fetch('/api/employees');
        return await res.json();
    }

    function drawRows() {
        tableBody.innerHTML = '';
        const [year, month] = monthInput.value.split('-').map(Number);
        const days = getDaysInMonth(year, month - 1);

        employees.forEach(emp => {
            const tr = document.createElement('tr');

            const tdName = document.createElement('td');
            tdName.className = 'sticky-col';
            tdName.textContent = emp.name;
            tdName.style.fontWeight = 'bold';
            tr.appendChild(tdName);

            for (let i = 1; i <= days; i++) {
                const td = document.createElement('td');
                td.className = 'editable shift-Empty';
                td.dataset.empId = emp.id;
                td.dataset.date = `${year}-${String(month).padStart(2, '0')}-${String(i).padStart(2, '0')}`;

                if (!isViewer) {
                    td.onclick = () => {
                        toggleShift(td);
                        calculateStats();
                    };
                } else {
                    td.classList.remove('editable');
                }

                tr.appendChild(td);
            }
            tableBody.appendChild(tr);
        });

        loadSchedules();
    }

    const shiftTypes = ['Empty', 'Holiday', 'Off', 'Day', 'Night'];

    function toggleShift(cell) {
        let currentClass = Array.from(cell.classList).find(c => c.startsWith('shift-')) || 'shift-Empty';
        let currentShift = currentClass.replace('shift-', '');

        let currentIndex = shiftTypes.indexOf(currentShift);
        if (currentIndex === -1) currentIndex = 0;

        let nextIndex = (currentIndex + 1) % shiftTypes.length;
        let nextShift = shiftTypes[nextIndex];

        updateCell(cell, nextShift);
    }

    function updateCell(cell, shift) {
        cell.className = cell.className.replace(/shift-\w+/g, '').trim();
        cell.classList.add(`shift-${shift}`);

        if (shift === 'Empty') cell.innerText = '';
        else if (shift === 'Day') cell.innerText = '주간';
        else if (shift === 'Night') cell.innerText = '야간';
        else if (shift === 'Off') cell.innerText = '휴무';
        else if (shift === 'Holiday') cell.innerText = '휴가';
        else cell.innerText = shift;
    }

    async function loadSchedules() {
        const [year, month] = monthInput.value.split('-').map(Number);
        const start = `${year}-${String(month).padStart(2, '0')}-01`;
        const end = `${year}-${String(month).padStart(2, '0')}-${getDaysInMonth(year, month - 1)}`;

        const res = await fetch(`/api/schedules?start=${start}&end=${end}`);
        const schedules = await res.json();

        schedules.forEach(sch => {
            const cell = document.querySelector(`td[data-emp-id="${sch.employee_id}"][data-date="${sch.date}"]`);
            if (cell) {
                updateCell(cell, sch.shift_type);
            }
        });
        calculateStats();
    }

    function calculateStats() {
        const stats = {};
        employees.forEach(e => {
            stats[e.id] = { name: e.name, Day: 0, Night: 0, Off: 0, Holiday: 0, Total: 0 };
        });

        document.querySelectorAll('td[data-emp-id]').forEach(td => {
            const empId = td.dataset.empId;
            const shiftClass = Array.from(td.classList).find(c => c.startsWith('shift-'));
            if (shiftClass && stats[empId]) {
                const shift = shiftClass.replace('shift-', '');
                if (stats[empId][shift] !== undefined) {
                    stats[empId][shift]++;
                    if (shift === 'Day' || shift === 'Night') {
                        stats[empId].Total++;
                    }
                }
            }
        });

        renderStats(stats);
    }

    function renderStats(stats) {
        const container = document.getElementById('statsContent');
        let html = `
            <table style="width: 100%; border-collapse: collapse; font-size: 0.85rem;">
                <thead>
                    <tr style="background: #f1f5f9;">
                        <th style="padding: 5px; border: 1px solid #ddd;">이름</th>
                        <th style="padding: 5px; border: 1px solid #ddd;">주간</th>
                        <th style="padding: 5px; border: 1px solid #ddd;">야간</th>
                        <th style="padding: 5px; border: 1px solid #ddd;">휴무</th>
                        <th style="padding: 5px; border: 1px solid #ddd;">휴가</th>
                        <th style="padding: 5px; border: 1px solid #ddd;">근무일</th>
                    </tr>
                </thead>
                <tbody>
        `;

        Object.values(stats).forEach(s => {
            html += `
                <tr>
                    <td style="padding: 5px; border: 1px solid #ddd;">${s.name}</td>
                    <td style="padding: 5px; border: 1px solid #ddd; font-weight: bold; color: #1e40af;">${s.Day}</td>
                    <td style="padding: 5px; border: 1px solid #ddd; font-weight: bold; color: #475569;">${s.Night}</td>
                    <td style="padding: 5px; border: 1px solid #ddd; color: #991b1b;">${s.Off}</td>
                    <td style="padding: 5px; border: 1px solid #ddd; color: #9a3412;">${s.Holiday}</td>
                    <td style="padding: 5px; border: 1px solid #ddd; font-weight: bold;">${s.Total}</td>
                </tr>
            `;
        });

        html += '</tbody></table>';
        container.innerHTML = html;
    }

    // --- Event Listeners ---

    // Modal Logic
    const modal = document.getElementById("settingsModal");
    const autoAssignBtn = document.getElementById("autoAssignBtn");
    const closeBtn = document.getElementsByClassName("close")[0];
    const runAutoAssignBtn = document.getElementById("runAutoAssign");

    autoAssignBtn.onclick = () => {
        modal.style.display = "block";
    }

    closeBtn.onclick = () => {
        modal.style.display = "none";
    }

    window.onclick = (event) => {
        if (event.target == modal) {
            modal.style.display = "none";
        }
    }

    runAutoAssignBtn.onclick = async () => {
        const minDay = document.getElementById('minDay').value;
        const minNight = document.getElementById('minNight').value;
        const [year, month] = monthInput.value.split('-').map(Number);

        // Disable button to prevent double click
        runAutoAssignBtn.disabled = true;
        runAutoAssignBtn.innerText = "배정 중...";

        try {
            const res = await fetch('/api/auto_assign', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    year: year,
                    month: month,
                    constraints: {
                        min_day: parseInt(minDay),
                        min_night: parseInt(minNight)
                    }
                })
            });

            const result = await res.json();
            if (res.ok) {
                alert(result.message);
                modal.style.display = "none";
                loadSchedules(); // Reload grid
            } else {
                alert("오류 발생: " + result.error);
            }
        } catch (e) {
            alert("서버 통신 오류");
        } finally {
            runAutoAssignBtn.disabled = false;
            runAutoAssignBtn.innerText = "배정 시작";
        }
    };

    addEmployeeBtn.onclick = async () => {
        const name = prompt("직원 이름을 입력하세요:");
        if (name) {
            await fetch('/api/employees', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ name })
            });
            renderGrid();
        }
    };

    document.getElementById('saveBtn').onclick = async () => {
        // Collect all data
        const updates = [];
        document.querySelectorAll('td.editable').forEach(td => {
            // Only send if it has a shift (optimization possible: only changed ones)
            // For now, let's just send what's visible or track changes. 
            // Better: Iterate all cells and save state.
            let shift = td.className.replace('editable ', '').replace('shift-', '');
            updates.push({
                employee_id: td.dataset.empId,
                date: td.dataset.date,
                shift_type: shift
            });
        });

        await fetch('/api/schedules', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(updates)
        });
        alert('저장되었습니다!');
    };

    document.getElementById('shareBtn').onclick = () => {
        const url = new URL(window.location.href);
        url.searchParams.set('mode', 'view');

        navigator.clipboard.writeText(url.toString()).then(() => {
            alert('공유 링크가 클립보드에 복사되었습니다!\n(보기 전용 모드)');
        }).catch(err => {
            console.error('Could not copy text: ', err);
            alert('링크: ' + url.toString());
        });
    };

    monthInput.onchange = () => {
        const [year, month] = monthInput.value.split('-').map(Number);
        renderHeader(year, month - 1);
        renderGrid();
    };

    // Initial Render
    const [y, m] = monthInput.value.split('-').map(Number);
    renderHeader(y, m - 1);
    renderGrid();
});
