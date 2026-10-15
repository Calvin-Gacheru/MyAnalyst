![alt text](school_logo.png)
# MyAnalyst: A Self-Reflecting Large Language Model Agent for Autonomous Data Analysis For Small and Medium-Sized Enterprises (SMEs)

* **NAME**: CALVIN GACHERU MWANGI
* **ADM**: 670035

## Problem Statement
Small and medium-sized enterprises (SMEs) often struggle to bridge the gap between raw data and actionable insights due to the high congnitive load and technical expertise required for effective data analysis. Traditional data analysis tools can be complex, requiring specialized knowledge in statistics, programming, data visualization, and domain-specific expertise. This complexity can lead to underutilization of data, missed opportunities, and suboptimal decision-making. SMEs need a solution that simplifies the data analysis process, making it accessible and actionable without requiring extensive technical skills.

Existing Automated Machine Learning (AutoML) tools have made strides in democratizing data analysis, but they often lack the ability to provide context-aware insights and self-reflecting capabilities. These tools typically focus on model selection and hyperparameter tuning, but they do not offer a comprehensive understanding of the data, nor do they provide actionable recommendations based on the analysis. Additionally, many AutoML tools are designed for larger organizations with more resources, making them less suitable for SMEs. 

## Project Objectives
* Develop MyAnalyst utilizing a planner-executor-reflector architecture for end-to-end SME data analysis.
* Enable self-reflection to catch errors, identify biases, and offer actionable recommendations.
* Evaluate performance using real-world datasets and established benchmarks.
* Generate comprehensive, interpretable reports for decision-makers.
* Build a non-technical, user-friendly interface.

## Target Audience and Beneficiaries
* Small and medium-sized enterprises (SMEs) and organizations needing simplified data analysis tools.

## Proposed Activities
1. **Literature Review and Benchmarking**: Conduct a thorough review of existing AutoML tools, self-reflecting AI agents, and data analysis methodologies to identify gaps and opportunities for improvement
2. **Architecture Design & Orchestration**: Design the planner-executor-reflector architecture for MyAnalyst, defining the state machine and interaction protocols between components.
3. **Data Preparation & Anti-Memorization Techniques**: Develop methods for efficient data handling, including data cleaning, transformation, and storage, while implementing anti-memorization techniques - obfuscation techniques, to prevent overfitting and ensure generalization.
4. **Data Preprocessing & Feature Engineering**: Implement automated data preprocessing and feature engineering techniques to prepare raw data for analysis, ensuring that the agent can handle various data formats and structures.
5. **Algorithm Development & Model Selection**: Constrain the agent's model pool to a predifines set of classical machine learning algorithms, and develop methods for model selection, hyperparameter tuning, and performance evaluation.
6. **Self-Reflection & Error Analysis**: Implement self-reflection mechanisms that allow MyAnalyst to evaluate its own performance, identify potential errors or biases, and provide recommendations for improvement. Engineer parsing algorithms to capture standard error, standars output, and model evaluation metrics to facilitate self-reflection and error analysis. Feed these outputs back into the LLM context window with specific diagnosis prompts to enable the agent to self-reflect and improve its analysis process.
7. **User Interface Development**: Create a user-friendly interface that allows SMEs to interact with MyAnalyst, input their data, and receive insights without requiring extensive technical knowledge. The interface should provide clear visualizations, summaries, and actionable recommendations based on the analysis performed by the agent.
8. **Evaluation & Benchmarking**: Conduct extensive testing and evaluation of MyAnalyst on established benchmarks and real-world datasets to assess its performance, reliability, and effectiveness in providing actionable insights for SMEs.

## Project Activities
* **Weeks 1-2:** Conduct literature reviews of AutoML and AI agents, establishing evaluation criteria.
* **Weeks 3-4:** Design the planner-executor-reflector state-machine architecture and define interaction protocols.
* **Weeks 5-8:** Execute data preparation using anti-memorization techniques, automate preprocessing, and implement feature engineering.
* **Weeks 9-10:** Develop algorithms restricted to classical machine learning models and implement cross-validation.
* **Weeks 11-12:** Engineer parsing algorithms to feed errors and metrics back into the LLM context window for self-reflection.
* **Weeks 13-14:** Develop the UI, conduct benchmark testing against existing tools, and gather user feedback.

## Methodology
* **Planner Node:** Generates action sequences using rule-based and machine learning techniques based on input data and objectives.
* **Executor Node:** Handles data preprocessing, model selection, and result interpretation.
* **Reflector Node:** Evaluates agent performance, identifies biases, and provides improvement recommendations.
```
       [ User Uploads CSV & Prompt ]
                    │
                    ▼
            ┌───────────────┐
    ┌──────►│ Planner Node  │◄──────────────┐
    │       └───────┬───────┘               │
    │               │                       │
    │               ▼                       │
(Re-Plan)   ┌───────────────┐               │
    │       │ Executor Node │ (Runs Python in Docker)
    │       └───────┬───────┘               │
    │               │                       │
    │               ▼                       │
    └───────┤ Observer Node ├───────────────┘
            └───────┬───────┘ (Passes statistical checks)
                    │
                    ▼
            ┌───────────────┐
            │ Reporter Node │ --> [ Final Business Report ]
            └───────────────┘
```

## Expected Outcomes
- A fully functional MyAnalyst agent capable of autonomously performing end-to-end data analysis tasks for organizations, including data preprocessing, model selection, and result interpretation.
- A self-reflecting mechanism that allows MyAnalyst to evaluate its own performance, identify potential errors or biases, and provide actionable recommendations for improvement.
- A comprehensive report summarizing the analysis process findings, and recommendations, which can be easily interpreted by decision-makers within organizations.
- A user-friendly interface that allows organizations to interact with MyAnalyst, input their data, and receive insights without requiring extensive technical knowledge.

