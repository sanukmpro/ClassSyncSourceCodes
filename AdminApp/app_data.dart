class AppData {
  static const List<String> departments = [
    'Computer Engineering',
    'Civil Engineering',
    'Mechanical Engineering'
  ];

  static const List<String> semesters = ['1', '2', '3', '4', '5', '6'];

  static const Map<String, Map<String, List<String>>> subjectMap = {
    'Computer Engineering': {
      '1': [
        'Communication Skills in English', 'Engineering Mathematics I', 'Engineering Physics I',
        'Engineering Chemistry I', 'Engineering Graphics', 'Computing Fundamentals', 'Workshop Practice'
      ],
      '2': [
        'English for Communication II', 'Engineering Mathematics II', 'Engineering Physics II',
        'Introduction to IT Systems', 'Engineering Mechanics', 'Environmental Science & Disaster Management',
        'Introduction to IT Systems Lab', 'Engineering Physics Lab', 'Engineering Chemistry Lab'
      ],
      '3': [
        'Computer Organization', 'Programming in C', 'Database Management Systems', 'Digital Electronics',
        'Programming in C Lab', 'Database Management Systems Lab', 'Digital Electronics Lab'
      ],
      '4': [
        'Object Oriented Programming', 'Computer Communication and Networks', 'Data Structures',
        'Operating Systems', 'Object Oriented Programming Lab', 'Computer Communication and Networks Lab',
        'Data Structures Lab', 'Minor Project'
      ],
      '5': [
        'Web Technology', 'Software Engineering', 'Microprocessor and Interfacing',
        'Program Elective I: Cloud Computing', 'Program Elective I: Embedded Systems', 'Program Elective I: Advanced Database Management Systems',
        'Open Elective I: Project Management', 'Open Elective I: Operations Research', 'Open Elective I: Introduction to Sustainable Development',
        'Web Technology Lab', 'Microprocessor and Interfacing Lab', 'Major Project (Phase I)'
      ],
      '6': [
        'Mobile Computing', 'Program Elective II: Network Security', 'Program Elective II: Artificial Intelligence', 'Program Elective II: Internet of Things',
        'Program Elective III: Smart Device Programming', 'Program Elective III: Information Storage & Management', 'Program Elective III: Software Testing',
        'Open Elective II: Entrepreneurship and Startup', 'Open Elective II: Introduction to E-Governance', 'Open Elective II: Energy Conservation and Management',
        'Software Testing Lab', 'Mobile Computing Lab', 'Seminar', 'Major Project (Phase II)'
      ],
    },
    'Civil Engineering': {
      '1': [
        'Communication Skills in English', 'Engineering Mathematics I', 'Engineering Physics I',
        'Engineering Chemistry I', 'Engineering Graphics', 'Computing Fundamentals', 'Workshop Practice'
      ],
      '2': [
        'English for Communication II', 'Engineering Mathematics II', 'Engineering Physics II',
        'Introduction to IT Systems', 'Engineering Mechanics', 'Environmental Science & Disaster Management',
        'Introduction to IT Systems Lab', 'Engineering Physics Lab', 'Engineering Chemistry Lab'
      ],
      '3': [
        'Construction Materials', 'Surveying - I', 'Mechanics of Solids', 'Civil Engineering Drawing',
        'Surveying Lab I', 'Construction Materials Lab', 'Civil Engineering Drawing Lab'
      ],
      '4': [
        'Hydraulics', 'Surveying - II', 'Theory of Structures', 'Concrete Technology',
        'Hydraulics Lab', 'Surveying Lab II', 'Materials Testing Lab', 'Minor Project'
      ],
      '5': [
        'Design of RCC Structures', 'Quantity Surveying & Valuation I', 'Geotechnical Engineering I',
        'Program Elective I: Water Resources Engineering', 'Program Elective I: Transportation Engineering', 'Program Elective I: Environmental Engineering I',
        'Open Elective I: Project Management', 'Open Elective I: Operations Research', 'Open Elective I: Introduction to Sustainable Development',
        'Computer Aided Design & Drafting Lab', 'Concrete Lab', 'Major Project (Phase I)'
      ],
      '6': [
        'Design of Steel Structures', 'Quantity Surveying & Valuation II', 'Construction Management',
        'Program Elective II: Geotechnical Engineering II', 'Program Elective II: Environmental Engineering II', 'Program Elective II: Advanced Construction Technology',
        'Program Elective III: Pavement Engineering', 'Program Elective III: Ground Improvement Techniques', 'Program Elective III: Town Planning & Architecture',
        'Open Elective II: Entrepreneurship and Startup', 'Open Elective II: Introduction to E-Governance', 'Open Elective II: Energy Conservation and Management',
        'Geotechnical Lab', 'Seminar', 'Major Project (Phase II)'
      ],
    },
    'Mechanical Engineering': {
      '1': [
        'Communication Skills in English', 'Engineering Mathematics I', 'Engineering Physics I',
        'Engineering Chemistry I', 'Engineering Graphics', 'Computing Fundamentals', 'Workshop Practice'
      ],
      '2': [
        'English for Communication II', 'Engineering Mathematics II', 'Engineering Physics II',
        'Introduction to IT Systems', 'Engineering Mechanics', 'Environmental Science & Disaster Management',
        'Introduction to IT Systems Lab', 'Engineering Physics Lab', 'Engineering Chemistry Lab'
      ],
      '3': [
        'Manufacturing Process', 'Thermal Engineering - I', 'Strength of Materials',
        'Mechanical Engineering Drawing', 'Strength of Materials Lab', 'Mechanical Engineering Drawing Lab', 'Workshop Practice II'
      ],
      '4': [
        'Fluid Mechanics & Machinery', 'Thermal Engineering - II', 'Manufacturing Technology', 'Metrology & Instrumentation',
        'Fluid Mechanics & Machinery Lab', 'Production Drawing Lab', 'Workshop Practice III', 'Minor Project'
      ],
      '5': [
        'Design of Machine Elements', 'Industrial Engineering', 'Theory of Machines',
        'Program Elective I: Automobile Engineering', 'Program Elective I: Power Plant Engineering', 'Program Elective I: Renewable Energy Sources',
        'Open Elective I: Project Management', 'Open Elective I: Operations Research', 'Open Elective I: Introduction to Sustainable Development',
        'Thermal Engineering Lab', 'Computer Aided Machine Drawing Lab', 'Major Project (Phase I)'
      ],
      '6': [
        'CIM & Robotics', 'Refrigeration & Air Conditioning',
        'Program Elective II: Maintenance Engineering', 'Program Elective II: Mechatronics', 'Program Elective II: Total Quality Management',
        'Program Elective III: Heating Ventilation & Air Conditioning', 'Program Elective III: Tool Engineering', 'Program Elective III: Industrial Robotics',
        'Open Elective II: Entrepreneurship and Startup', 'Open Elective II: Introduction to E-Governance', 'Open Elective II: Energy Conservation and Management',
        'Machine Tool Installation & Maintenance Lab', 'Production Lab', 'Seminar', 'Major Project (Phase II)'
      ],
    },
  };
}