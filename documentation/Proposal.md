# MyAnalyst: Self Reflecting Large Language Model Agent for Autonomous Data Analysis

## Introduction

In the era of big data, the ability to analyze and interpret vast amounts of information is crucial for businesses and researchers alike. Traditional data analysis methods often require significant human intervention, which can be time-consuming and prone to error. To address these challenges, we propose the development of MyAnalyst, a self-reflecting large language model (LLM) agent designed to autonomously analyze data and provide insights with minimal human oversight. MyAnalyst leverages advanced natural language processing (NLP) techniques and machine learning algorithms to understand complex datasets, generate hypotheses, and offer actionable recommendations. 

## Executive Summary

Organizations collect vast amounts of tabular data but often lack the specialized human resources required to clean, analyze, and extract actionable insights. While traditional Automated Machine Learning (AutoML) tools efficiently streamline model selection and hyperparameter tuning, they lack the cognitive reasoning to interpret data context, explain business insights, or self-correct when encountering analytical errors (He et al., 2021).

This project proposes MyAnalyst, an autonomous, Large Language Model (LLM)-powered agent designed to execute end-to-end data analysis workflows. Utilizing a planner-executor-reflector architecture based on the ReAct framework (Yao et al., 2023), MyAnalyst ingests structured datasets, formulates an analysis strategy, and writes Python code to execute data cleaning, exploratory data analysis (EDA), and model training using classic scikit-learn algorithms. Crucially, the system features a self-reflection loop, allowing it to autonomously detect code errors or suboptimal model performance and dynamically revise its approach without human intervention.

The final deliverable will be a proof-of-concept application accessed via a Gradio web interface, which ultimately generates a comprehensive, natural-language business report. By bridging the gap between raw tabular data and strategic decision-making, MyAnalyst aims to democratize access to data science capabilities (aligning with UN SDG 9: Industry, Innovation and Infrastructure) and serves as a benchmark for testing the reasoning limits of modern LLMs in structured data environments.



## References

He, X., Zhao, K., & Chu, X. (2021). AutoML: A survey of the state-of-the-art. Knowledge-Based Systems, 212, 106622. https://doi.org/10.1016/j.knosys.2020.106622

Yao, S., Zhao, J., Yu, D., Du, N., Shafran, I., Narasimhan, K., & Cao, Y. (2023). ReAct: Synergizing reasoning and acting in language models. arXiv preprint arXiv:2210.03629.