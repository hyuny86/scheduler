from flask import Flask, render_template, request, jsonify
from models import db, Employee, Schedule, DailyInfo
from datetime import datetime, timedelta
import os

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///schedule.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db.init_app(app)

with app.app_context():
    db.create_all()
    if not Employee.query.first():
        default_names = [
            "도광록 SM", "권누리 DM", "이민호 SCA", "배지연 SCA", "이윤조 SCA",
            "이현창 CA", "박현태 CA", "박성언 CA", "조원우 CA", "임수혁 SA"
        ]
        for name in default_names:
            db.session.add(Employee(name=name))
        db.session.commit()

@app.route('/')
def index():
    return render_template('index.html')

# --- API Endpoints ---

@app.route('/api/employees', methods=['GET', 'POST'])
def manage_employees():
    if request.method == 'POST':
        data = request.json
        new_employee = Employee(name=data['name'])
        db.session.add(new_employee)
        db.session.commit()
        return jsonify(new_employee.to_dict()), 201
    
    employees = Employee.query.all()
    return jsonify([e.to_dict() for e in employees])

@app.route('/api/employees/<int:id>', methods=['PUT', 'DELETE'])
def manage_employee_item(id):
    employee = Employee.query.get_or_404(id)
    if request.method == 'DELETE':
        db.session.delete(employee)
        db.session.commit()
        return jsonify({'message': 'Deleted'}), 200
    
    data = request.json
    employee.name = data.get('name', employee.name)
    db.session.commit()
    return jsonify(employee.to_dict())

@app.route('/api/schedules', methods=['GET', 'POST'])
def manage_schedules():
    if request.method == 'POST':
        data = request.json
        # Expecting a list of updates or a single update
        # For simplicity, let's handle single update or bulk
        # data format example: { 'employee_id': 1, 'date': '2023-10-27', 'shift_type': 'Day' }
        
        updates = data if isinstance(data, list) else [data]
        
        for item in updates:
            date_obj = datetime.strptime(item['date'], '%Y-%m-%d').date()
            schedule = Schedule.query.filter_by(employee_id=item['employee_id'], date=date_obj).first()
            
            if item['shift_type'] == 'Empty':
                if schedule:
                    db.session.delete(schedule)
            else:
                if schedule:
                    schedule.shift_type = item['shift_type']
                else:
                    new_schedule = Schedule(
                        employee_id=item['employee_id'],
                        date=date_obj,
                        shift_type=item['shift_type']
                    )
                    db.session.add(new_schedule)
        
        db.session.commit()
        return jsonify({'message': 'Schedule updated'}), 200

    # GET: return schedules for a specific range usually
    start_date_str = request.args.get('start')
    end_date_str = request.args.get('end')
    
    query = Schedule.query
    if start_date_str and end_date_str:
        start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
        end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
        query = query.filter(Schedule.date >= start_date, Schedule.date <= end_date)
        
    schedules = query.all()
    return jsonify([s.to_dict() for s in schedules])

@app.route('/api/auto_assign', methods=['POST'])
def auto_assign():
    data = request.json
    year = data['year']
    month = data['month']
    constraints = data['constraints']
    min_day = constraints.get('min_day', 2)
    min_night = constraints.get('min_night', 1)

    import calendar
    import random

    _, num_days = calendar.monthrange(year, month)
    employees = Employee.query.all()
    if not employees:
        return jsonify({'error': 'No employees found'}), 400

    # Retrieve existing schedules (Holidays/Offs set by user)
    existing_schedules = Schedule.query.filter(
        db.extract('year', Schedule.date) == year,
        db.extract('month', Schedule.date) == month
    ).all()

    # Create a map for quick lookup: (employee_id, day) -> shift_type
    schedule_map = {}
    for s in existing_schedules:
        schedule_map[(s.employee_id, s.date.day)] = s.shift_type

    # Working copy of the schedule
    # Format: day -> {'Day': [emp_ids], 'Night': [emp_ids], 'Off': [emp_ids]}
    daily_assignments = {day: {'Day': [], 'Night': [], 'Off': [], 'Holiday': []} for day in range(1, num_days + 1)}

    # Pre-fill with existing fixed shifts
    for emp in employees:
        for day in range(1, num_days + 1):
            current_shift = schedule_map.get((emp.id, day))
            if current_shift == 'Holiday':
                daily_assignments[day]['Holiday'].append(emp.id)
            elif current_shift == 'Off': # Explicit Off
                daily_assignments[day]['Off'].append(emp.id)
            elif current_shift in ['Day', 'Night']:
                # Respect manual assignments if we want, or overwrite? 
                # Request says "User designates holidays first, assigns rest logic".
                # Let's assume manual 'Day'/'Night' are fixed too if present, 
                # but 'Off' might be flexible if not 'Holiday'? 
                # For this implementation, I'll treat all existing entries as FIXED constraints.
                daily_assignments[day][current_shift].append(emp.id)

    new_schedule_entries = []

    # Greedy allocation logic
    for day in range(1, num_days + 1):
        # Identify available employees (not in Holiday/Off/Day/Night already)
        assigned_ids = [eid for shift in daily_assignments[day].values() for eid in shift]
        available_employees = [e for e in employees if e.id not in assigned_ids]
        
        # Shuffle to randomize fairness
        random.shuffle(available_employees)
        
        # Fill Night shift first (usually harder/less preferred)
        needed_night = max(0, min_night - len(daily_assignments[day]['Night']))
        for _ in range(needed_night):
            if available_employees:
                emp = available_employees.pop()
                daily_assignments[day]['Night'].append(emp.id)
                new_schedule_entries.append((emp.id, day, 'Night'))
        
        # Fill Day shift
        needed_day = max(0, min_day - len(daily_assignments[day]['Day']))
        for _ in range(needed_day):
            if available_employees:
                emp = available_employees.pop()
                daily_assignments[day]['Day'].append(emp.id)
                new_schedule_entries.append((emp.id, day, 'Day'))
        
        # Rest are Off? Or unassigned? Let's mark them as Off for now to complete the schedule
        while available_employees:
            emp = available_employees.pop()
            daily_assignments[day]['Off'].append(emp.id)
            new_schedule_entries.append((emp.id, day, 'Off'))

    # Commit changes
    try:
        for emp_id, day, shift in new_schedule_entries:
            date_obj = datetime(year, month, day).date()
            # Check if exists (it shouldn't if we filtered correctly, but safety first)
            existing = Schedule.query.filter_by(employee_id=emp_id, date=date_obj).first()
            if existing:
                if existing.shift_type not in ['Holiday', 'Day', 'Night']: # Overwrite only if not fixed?
                    existing.shift_type = shift
            else:
                db.session.add(Schedule(employee_id=emp_id, date=date_obj, shift_type=shift))
        
        db.session.commit()
        return jsonify({'message': '자동 배정 완료'}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': str(e)}), 500

from models import db, Employee, Schedule, DailyInfo

# ...

@app.route('/api/daily_info', methods=['GET', 'POST'])
def manage_daily_info():
    if request.method == 'POST':
        data = request.json # List of {date, stock, event}
        updates = data if isinstance(data, list) else [data]
        for item in updates:
            date_obj = datetime.strptime(item['date'], '%Y-%m-%d').date()
            info = DailyInfo.query.filter_by(date=date_obj).first()
            if info:
                info.stock = item.get('stock', info.stock)
                info.event = item.get('event', info.event)
            else:
                new_info = DailyInfo(date=date_obj, stock=item.get('stock', ''), event=item.get('event', ''))
                db.session.add(new_info)
        db.session.commit()
        return jsonify({'message': 'Daily info updated'}), 200

    start_date_str = request.args.get('start')
    end_date_str = request.args.get('end')
    query = DailyInfo.query
    if start_date_str and end_date_str:
        start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
        end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
        query = query.filter(DailyInfo.date >= start_date, DailyInfo.date <= end_date)
    
    return jsonify([i.to_dict() for i in query.all()])

if __name__ == '__main__':
    app.run(debug=True)
