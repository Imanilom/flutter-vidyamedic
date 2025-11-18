import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class HealthQuestionnairePage extends StatefulWidget {
  @override
  _HealthQuestionnairePageState createState() => _HealthQuestionnairePageState();
}

class _HealthQuestionnairePageState extends State<HealthQuestionnairePage> {
  final PageController _pageController = PageController();
  int currentQuestionIndex = 0;
  bool isLoading = false;
  
  // Store all answers
  Map<String, dynamic> answers = {};
  
  // Define all questions - original 13 + 7 IPAQ questions = 20 questions
  final List<Map<String, dynamic>> questions = [
    {
      'id': 'age',
      'title': 'What is your age?',
      'type': 'number',
      'subtitle': 'This helps us understand age-related health patterns',
      'required': true,
      'min': 15,
      'max': 120,
    },
    {
      'id': 'gender',
      'title': 'What is your gender?',
      'type': 'single_choice',
      'subtitle': 'For health data analysis purposes',
      'required': true,
      'options': ['Male', 'Female', 'Other', 'Prefer not to say']
    },
    {
      'id': 'height',
      'title': 'What is your height? (cm)',
      'type': 'number',
      'subtitle': 'Used for BMI and health calculations',
      'required': true,
      'min': 100,
      'max': 250,
    },
    {
      'id': 'weight',
      'title': 'What is your weight? (kg)',
      'type': 'number',
      'subtitle': 'Used for BMI and health calculations',
      'required': true,
      'min': 30,
      'max': 300,
    },
    // IPAQ QUESTIONS START HERE
    {
      'id': 'ipaq_vigorous_days',
      'title': 'During the last 7 days, on how many days did you do VIGOROUS physical activities?',
      'type': 'number',
      'subtitle': 'Vigorous activities: heavy lifting, digging, aerobics, or fast bicycling (at least 10 minutes at a time)',
      'required': true,
      'min': 0,
      'max': 7,
      'skipLogic': {
        'condition': 'equals',
        'value': 0,
        'skipTo': 'ipaq_moderate_days'
      }
    },
    {
      'id': 'ipaq_vigorous_time',
      'title': 'How much time did you usually spend doing VIGOROUS physical activities on one of those days?',
      'type': 'time_input',
      'subtitle': 'Please enter hours and minutes you spent on vigorous activities per day',
      'required': true,
    },
    {
      'id': 'ipaq_moderate_days',
      'title': 'During the last 7 days, on how many days did you do MODERATE physical activities?',
      'type': 'number',
      'subtitle': 'Moderate activities: carrying light loads, bicycling at regular pace, doubles tennis (at least 10 minutes at a time). Do not include walking.',
      'required': true,
      'min': 0,
      'max': 7,
      'skipLogic': {
        'condition': 'equals',
        'value': 0,
        'skipTo': 'ipaq_walking_days'
      }
    },
    {
      'id': 'ipaq_moderate_time',
      'title': 'How much time did you usually spend doing MODERATE physical activities on one of those days?',
      'type': 'time_input',
      'subtitle': 'Please enter hours and minutes you spent on moderate activities per day',
      'required': true,
    },
    {
      'id': 'ipaq_walking_days',
      'title': 'During the last 7 days, on how many days did you walk for at least 10 minutes at a time?',
      'type': 'number',
      'subtitle': 'Include walking at work, home, travel, and for recreation/sport/exercise',
      'required': true,
      'min': 0,
      'max': 7,
      'skipLogic': {
        'condition': 'equals',
        'value': 0,
        'skipTo': 'ipaq_sitting_time'
      }
    },
    {
      'id': 'ipaq_walking_time',
      'title': 'How much time did you usually spend walking on one of those days?',
      'type': 'time_input',
      'subtitle': 'Please enter hours and minutes you spent walking per day',
      'required': true,
    },
    {
      'id': 'ipaq_sitting_time',
      'title': 'During the last 7 days, how much time did you spend sitting on a week day?',
      'type': 'time_input',
      'subtitle': 'Include time at work, home, coursework, leisure (sitting at desk, visiting friends, reading, watching TV)',
      'required': true,
    },
    // ORIGINAL QUESTIONS CONTINUE
    {
      'id': 'activity_level',
      'title': 'How would you describe your physical activity level?',
      'type': 'single_choice',
      'subtitle': 'Choose the option that best describes your typical week',
      'required': true,
      'options': [
        'Sedentary (little to no exercise)',
        'Lightly active (light exercise 1-3 days/week)',
        'Moderately active (moderate exercise 3-5 days/week)',
        'Very active (hard exercise 6-7 days/week)',
        'Extremely active (very hard exercise, physical job)'
      ]
    },
    {
      'id': 'smoking_status',
      'title': 'What is your smoking status?',
      'type': 'single_choice',
      'subtitle': 'This information helps assess cardiovascular risk',
      'required': true,
      'options': [
        'Never smoked',
        'Former smoker (quit more than 1 year ago)',
        'Recent former smoker (quit within 1 year)',
        'Current smoker (less than 1 pack/day)',
        'Current smoker (1 or more packs/day)'
      ]
    },
    {
      'id': 'alcohol_consumption',
      'title': 'How often do you consume alcohol?',
      'type': 'single_choice',
      'subtitle': 'Select your typical alcohol consumption pattern',
      'required': true,
      'options': [
        'Never',
        'Rarely (few times a year)',
        'Occasionally (1-2 times per month)',
        'Regularly (1-2 times per week)',
        'Frequently (3-4 times per week)',
        'Daily'
      ]
    },
    {
      'id': 'sleep_hours',
      'title': 'How many hours of sleep do you typically get per night?',
      'type': 'single_choice',
      'subtitle': 'Choose your average sleep duration',
      'required': true,
      'options': [
        'Less than 5 hours',
        '5-6 hours',
        '6-7 hours',
        '7-8 hours',
        '8-9 hours',
        'More than 9 hours'
      ]
    },
    {
      'id': 'stress_level',
      'title': 'How would you rate your current stress level?',
      'type': 'scale',
      'subtitle': 'Rate from 1 (very low stress) to 10 (very high stress)',
      'required': true,
      'min': 1,
      'max': 10,
    },
    {
      'id': 'chronic_conditions',
      'title': 'Do you have any of the following chronic conditions?',
      'type': 'multiple_choice',
      'subtitle': 'Select all that apply (this helps us understand your health context)',
      'required': false,
      'options': [
        'Diabetes',
        'High blood pressure (Hypertension)',
        'Heart disease',
        'Asthma',
        'Arthritis',
        'Depression or anxiety',
        'Thyroid disorders',
        'None of the above'
      ]
    },
    {
      'id': 'medications',
      'title': 'Are you currently taking any medications?',
      'type': 'single_choice',
      'subtitle': 'This may affect heart rate and other measurements',
      'required': true,
      'options': [
        'No medications',
        'Over-the-counter medications only',
        'Prescription medications (1-2 types)',
        'Multiple prescription medications (3 or more)',
        'Prefer not to answer'
      ]
    },
    {
      'id': 'exercise_frequency',
      'title': 'How many days per week do you engage in structured exercise?',
      'type': 'single_choice',
      'subtitle': 'Include gym, sports, running, cycling, etc.',
      'required': true,
      'options': [
        '0 days',
        '1-2 days',
        '3-4 days',
        '5-6 days',
        '7 days'
      ]
    },
    {
      'id': 'health_goals',
      'title': 'What are your primary health and fitness goals?',
      'type': 'multiple_choice',
      'subtitle': 'Select all that apply to help us understand your objectives',
      'required': true,
      'options': [
        'Weight management',
        'Improve cardiovascular fitness',
        'Build muscle strength',
        'Reduce stress',
        'Better sleep quality',
        'General health monitoring',
        'Athletic performance',
        'Medical condition management'
      ]
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadPreviousAnswers();
  }

  Future<void> _loadPreviousAnswers() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAnswers = prefs.getString('health_questionnaire_answers');
    if (savedAnswers != null) {
      setState(() {
        answers = json.decode(savedAnswers);
      });
    }
  }

  Future<void> _saveAnswer(String questionId, dynamic answer) async {
    setState(() {
      answers[questionId] = answer;
    });
    
    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('health_questionnaire_answers', json.encode(answers));
  }

  void _handleSkipLogic(int currentIndex) {
    final currentQuestion = questions[currentIndex];
    if (currentQuestion.containsKey('skipLogic')) {
      final skipLogic = currentQuestion['skipLogic'];
      final currentAnswer = answers[currentQuestion['id']];
      
      if (skipLogic['condition'] == 'equals' && currentAnswer == skipLogic['value']) {
        final skipToId = skipLogic['skipTo'];
        final skipToIndex = questions.indexWhere((q) => q['id'] == skipToId);
        
        if (skipToIndex != -1 && skipToIndex > currentIndex) {
          setState(() {
            currentQuestionIndex = skipToIndex;
          });
          _pageController.jumpToPage(skipToIndex);
        }
      }
    }
  }

  Future<void> _submitQuestionnaire() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Calculate IPAQ score
      final ipaqScore = _calculateIPAQScore();
      
      // Save completion timestamp
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('health_questionnaire_completed', DateTime.now().toIso8601String());
      await prefs.setString('health_questionnaire_final_answers', json.encode(answers));
      await prefs.setInt('ipaq_score', ipaqScore);

      // Show success dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Questionnaire Completed!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 64),
              SizedBox(height: 16),
              Text('Thank you for completing the health questionnaire. Your responses have been saved and will help provide better health insights.'),
              SizedBox(height: 16),
              Text(
                'IPAQ Score: $ipaqScore MET-min/week',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Go back to previous screen
              },
              child: Text('Continue'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving responses. Please try again.')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  int _calculateIPAQScore() {
    // IPAQ scoring calculation based on guidelines
    int vigorousDays = answers['ipaq_vigorous_days'] ?? 0;
    int moderateDays = answers['ipaq_moderate_days'] ?? 0;
    int walkingDays = answers['ipaq_walking_days'] ?? 0;
    
    // Convert time inputs to minutes
    int vigorousMinutes = _convertTimeToMinutes(answers['ipaq_vigorous_time']);
    int moderateMinutes = _convertTimeToMinutes(answers['ipaq_moderate_time']);
    int walkingMinutes = _convertTimeToMinutes(answers['ipaq_walking_time']);
    
    // MET values according to IPAQ guidelines
    const int vigorousMET = 8;
    const int moderateMET = 4;
    const double walkingMET = 3.3;
    
    // Calculate MET-min/week for each category
    int vigorousMETMin = vigorousDays * vigorousMinutes * vigorousMET;
    int moderateMETMin = moderateDays * moderateMinutes * moderateMET;
    int walkingMETMin = walkingDays * walkingMinutes * walkingMET.toInt();
    
    // Total physical activity = sum of all categories
    return vigorousMETMin + moderateMETMin + walkingMETMin;
  }

  int _convertTimeToMinutes(dynamic timeData) {
    if (timeData is Map) {
      int hours = timeData['hours'] ?? 0;
      int minutes = timeData['minutes'] ?? 0;
      return (hours * 60) + minutes;
    }
    return 0;
  }

  bool _isQuestionAnswered(int index) {
    final question = questions[index];
    final answer = answers[question['id']];
    
    if (answer == null) return false;
    
    // Special handling for time input type
    if (question['type'] == 'time_input') {
      if (answer is Map) {
        return (answer['hours'] ?? 0) > 0 || (answer['minutes'] ?? 0) > 0;
      }
      return false;
    }
    
    return true;
  }

  bool _canProceed() {
    final currentQuestion = questions[currentQuestionIndex];
    if (currentQuestion['required'] == true) {
      return _isQuestionAnswered(currentQuestionIndex);
    }
    return true;
  }

  void _nextQuestion() {
    if (currentQuestionIndex < questions.length - 1) {
      // Apply skip logic before moving to next question
      _handleSkipLogic(currentQuestionIndex);
      
      // Only proceed if we're not skipping
      if (currentQuestionIndex < questions.length - 1) {
        setState(() {
          currentQuestionIndex++;
        });
        _pageController.nextPage(
          duration: Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _previousQuestion() {
    if (currentQuestionIndex > 0) {
      setState(() {
        currentQuestionIndex--;
      });
      _pageController.previousPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildQuestionWidget(Map<String, dynamic> question) {
    final questionId = question['id'];
    final currentAnswer = answers[questionId];

    switch (question['type']) {
      case 'number':
        return _buildNumberQuestion(question, currentAnswer);
      case 'single_choice':
        return _buildSingleChoiceQuestion(question, currentAnswer);
      case 'multiple_choice':
        return _buildMultipleChoiceQuestion(question, currentAnswer);
      case 'scale':
        return _buildScaleQuestion(question, currentAnswer);
      case 'time_input':
        return _buildTimeInputQuestion(question, currentAnswer);
      default:
        return Container();
    }
  }

  Widget _buildNumberQuestion(Map<String, dynamic> question, dynamic currentAnswer) {
    final controller = TextEditingController();
    if (currentAnswer != null) {
      controller.text = currentAnswer.toString();
    }

    return Column(
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Enter number of days (0-7)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          onChanged: (value) {
            final numValue = int.tryParse(value);
            if (numValue != null) {
              final min = question['min'] ?? 0;
              final max = question['max'] ?? 1000;
              if (numValue >= min && numValue <= max) {
                _saveAnswer(question['id'], numValue);
              }
            }
          },
        ),
        if (question['min'] != null && question['max'] != null)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Valid range: ${question['min']} - ${question['max']}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildTimeInputQuestion(Map<String, dynamic> question, dynamic currentAnswer) {
    Map<String, int> timeData = {
      'hours': 0,
      'minutes': 0,
    };
    
    if (currentAnswer is Map) {
      timeData = Map<String, int>.from(currentAnswer);
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text('Hours'),
                  SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: timeData['hours'],
                    items: List.generate(25, (index) => index)
                        .map((hour) => DropdownMenuItem(
                              value: hour,
                              child: Text('$hour hours'),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        timeData['hours'] = value ?? 0;
                        _saveAnswer(question['id'], timeData);
                      });
                    },
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  Text('Minutes'),
                  SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: timeData['minutes'],
                    items: List.generate(60, (index) => index)
                        .map((minute) => DropdownMenuItem(
                              value: minute,
                              child: Text('$minute min'),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        timeData['minutes'] = value ?? 0;
                        _saveAnswer(question['id'], timeData);
                      });
                    },
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Total: ${timeData['hours']} hours ${timeData['minutes']} minutes',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSingleChoiceQuestion(Map<String, dynamic> question, dynamic currentAnswer) {
    return Column(
      children: question['options'].map<Widget>((option) {
        return RadioListTile<String>(
          title: Text(option),
          value: option,
          groupValue: currentAnswer,
          onChanged: (value) {
            _saveAnswer(question['id'], value);
          },
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        );
      }).toList(),
    );
  }

  Widget _buildMultipleChoiceQuestion(Map<String, dynamic> question, dynamic currentAnswer) {
    List<String> selectedOptions = [];
    if (currentAnswer is List) {
      selectedOptions = List<String>.from(currentAnswer);
    }

    return Column(
      children: question['options'].map<Widget>((option) {
        return CheckboxListTile(
          title: Text(option),
          value: selectedOptions.contains(option),
          onChanged: (bool? value) {
            setState(() {
              if (value == true) {
                selectedOptions.add(option);
              } else {
                selectedOptions.remove(option);
              }
              _saveAnswer(question['id'], selectedOptions.toList());
            });
          },
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        );
      }).toList(),
    );
  }

  Widget _buildScaleQuestion(Map<String, dynamic> question, dynamic currentAnswer) {
    final min = question['min'] ?? 1;
    final max = question['max'] ?? 10;
    double value = currentAnswer?.toDouble() ?? min.toDouble();

    return Column(
      children: [
        Slider(
          value: value,
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          label: value.round().toString(),
          onChanged: (newValue) {
            setState(() {
              _saveAnswer(question['id'], newValue.round());
            });
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$min (Very low)'),
            Text('Current: ${value.round()}'),
            Text('$max (Very high)'),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = (currentQuestionIndex + 1) / questions.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Health & Physical Activity Questionnaire'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Progress indicator
          Container(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Question ${currentQuestionIndex + 1} of ${questions.length}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                ),
              ],
            ),
          ),
          // Question content
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: NeverScrollableScrollPhysics(), // Disable swipe
              onPageChanged: (index) {
                setState(() {
                  currentQuestionIndex = index;
                });
              },
              itemCount: questions.length,
              itemBuilder: (context, index) {
                final question = questions[index];
                return SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // IPAQ badge for IPAQ questions
                          if (question['id'].startsWith('ipaq'))
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.fitness_center, size: 16, color: Colors.green.shade800),
                                  SizedBox(width: 4),
                                  Text(
                                    'IPAQ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (question['id'].startsWith('ipaq')) SizedBox(height: 8),
                          
                          Text(
                            question['title'],
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          if (question['subtitle'] != null) ...[
                            SizedBox(height: 8),
                            Text(
                              question['subtitle'],
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                          if (question['required'] == true) ...[
                            SizedBox(height: 4),
                            Text(
                              '* Required',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          SizedBox(height: 24),
                          _buildQuestionWidget(question),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Navigation buttons
          Container(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                if (currentQuestionIndex > 0)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _previousQuestion,
                      icon: Icon(Icons.arrow_back),
                      label: Text('Previous'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade600,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                if (currentQuestionIndex > 0) SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _canProceed() ? 
                      (currentQuestionIndex == questions.length - 1 ? 
                        _submitQuestionnaire : 
                        _nextQuestion) : 
                      null,
                    icon: isLoading ? 
                      SizedBox(
                        width: 16, 
                        height: 16, 
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      ) :
                      Icon(currentQuestionIndex == questions.length - 1 ? 
                        Icons.check : 
                        Icons.arrow_forward),
                    label: Text(
                      isLoading ? 
                        'Submitting...' :
                        (currentQuestionIndex == questions.length - 1 ? 
                          'Submit' : 
                          'Next')
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}