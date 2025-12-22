extends PanelContainer

signal accepted

@export_file("*.md") var tos_path: String = "res://docs/tos.md"
@export_file("*.md") var privacy_path: String = "res://docs/privacy.md"
@export_range(0.5, 5.0, 0.1) var required_hold_time: float = 1.5

const DEFAULT_PRIVACY_TEXT := """
SCENEXR PRIVACY POLICY

Last Updated: December 22, 2025

Welcome to SceneXR! We at ANY Reality LLC ("Company," "we," "us," or "our") respect your privacy and have composed this Privacy Policy to help you understand how we process your Personal Data (defined below) and your choices about the data we process.

In this Privacy Policy, we refer to the SceneXR game as the “Game” and the SceneXR website scenexr.com as the “Site”. We also refer to the Game and the Site collectively as the “Services”.

This Privacy Policy explains what Personal Data (defined below) we collect in connection with the Services, how we use and share that data, and your choices concerning our data practices. This policy applies only to information we collect via the Services and in email, text, and other electronic communications sent through or in connection with the Services.

This policy DOES NOT apply to information that you provide to or is collected by any third party (except as described under "Third-Party Information Collection"), or which is collected outside of the Services.

This Privacy Policy is incorporated into and forms part of our Terms of Service scenexr.com/terms-of-services.

Before using the Services or submitting any Personal Data to Company, please review this Privacy Policy carefully and contact us at the email address below if you have any questions.

By using the Services, you acknowledge that you have read and understood the practices described in this Privacy Policy. If you do not agree with our policies and practices, do not download, register with, or use the Services.

1. DATA CONTROLLER / BUSINESS

ANY Reality LLC will be the entity responsible for your data (acting as a "controller" or "business" depending on applicable privacy laws). To ask questions or comment about this privacy policy and our privacy practices, you can contact us at:

Email: hello@scenexr.com

2. CHILDREN'S PRIVACY

Our Services are not directed to or intended for children who are under the age of 13 without appropriate parental consent and supervision as described herein. ANY Reality LLC does not knowingly collect Personal Data directly from children under the age of 13 in a manner inconsistent with the Children’s Online Privacy Protection Act (COPPA) or similar applicable laws.

If we learn we have collected or received Personal Data from a child under 13 (or a higher age if stipulated by local law, e.g., under 16 in some European jurisdictions without verified parental consent where required) without verification of parental consent where necessary, we will take steps to delete that information. If you have reason to believe that a child under the applicable age has provided Personal Data to ANY Reality LLC through the Services in a non-compliant manner, please contact us at hello@scenexr.com, and we will endeavor to delete that information from our databases.

The gameplay experience for users who identify themselves as being under the age of 13, or who are identified by Meta (our primary platform provider) as being under 13, may be automatically restricted to limit the processing of personal information in accordance with platform policies and applicable law. If you are the parent or legal guardian of a child and you would like your child to be permitted to play the Game, Meta allows you to create an age-restricted account for your child called a Parent-Managed Meta account. You can find more information about Meta Parent-Managed accounts here. Parents or guardians are responsible for monitoring their child’s use of the Services, including their interactions and any User Content they create or share.

3. PERSONAL DATA WE COLLECT

We collect information that alone or in combination with other information in our possession could be used to identify you (“Personal Data”) as follows:

Personal Data You Provide:

    Account Information (via Platform): When you access the Game, typically through a platform like Meta Quest, we receive account information from that platform, such as your platform User ID (e.g., Oculus User ID), platform username (e.g., Oculus username), and platform profile picture.

    Communications with Us: When you contact us directly (e.g., for support, to provide feedback, or regarding this Privacy Policy), we will collect the Personal Data you choose to include in your communications (e.g., your email address, name, and the content of your message).

    In-Game Communications & User Content: When you use the Game, you may create or share content and communicate with other players. This includes:

        User-Generated Content: Information related to your custom builds, map modifications, and other creations within the Game (e.g., content itself, creator ID, creation date).

        Voice Chat: If you use in-game voice chat, your voice communications may be processed.

        Text Chat (if applicable): If the Game includes text chat, we will process the content of those messages.

    Purchases: If you make in-app purchases, the platform (e.g., Meta) processes the payment, but we may receive information about your purchase history (e.g., items purchased, date, platform transaction ID) to fulfill your order and for our records. We do not directly collect or store your payment card details.

Automatically Collected Information (Usage Data):

When you visit, use, and interact with the Services, we and our third-party service providers may receive certain information about your visit, use, or interactions.

    In the Game: We may collect:

        Device Information: Device ID, VR headset type, operating system, IP address (which may be used to derive an approximate geographic location).

        Gameplay Information: Usage details such as time spent in the Game, features used, levels played, game progress, achievements, interactions with game elements, User Content created or interacted with, and other gameplay statistics.

        Technical Information: Crash reports, error logs, performance data, and other technical information to help us diagnose and fix issues.

        Multiplayer Information (if applicable): Session data, interactions with other players (e.g., joining a session, in-game actions relative to others).

    Cookies and Similar Technologies:

        Site Cookies (if applicable): A “cookie” is a piece of information sent to your browser by a website you visit. Our Site may use session cookies (which expire when you close your browser or after a set time) and persistent cookies (which remain on your device for a longer period). These may include strictly necessary cookies for site functionality, and potentially analytics or preference cookies if you implement them. For more details on cookies please visit All About Cookies.

		Game Technologies: The Game itself may use local storage on your device to save preferences, game state, or identifiers, but these are generally not "cookies" in the web sense. We do not use tracking cookies for advertising purposes within the Game environment itself.

    Location Data: We may derive an approximate geographic location from your IP address to understand general user distribution, for regional content (if any), or for security purposes. We do not collect precise geolocation data through GPS or similar technologies without your explicit consent.

    Do Not Track Signals: Our Services (including the Site, if any) currently do not respond to “Do Not Track” (“DNT”) signals and operate as described in this Privacy Policy whether or not a DNT signal is received. If we do so in the future, we will update this Privacy Policy.

Third-Party Information Collection Through the Services:

Some features of the Services are supported by third-party services. When you use our Services, these third parties may use automatic information collection technologies to collect information about you or your device. The Personal Data that we receive from these Third-Party Services is covered by this Privacy Policy, while their independent processing of your information is covered by their respective privacy policies.

Please see the list of key Third-Party Services we may use:

    Meta: As the primary platform for SceneXR on Quest devices, Meta collects data according to its policies. For more information visit: https://www.meta.com/legal/privacy-policy/

    Nakama: https://heroiclabs.com/privacy-policy/

    LiveKit: https://livekit.io/privacy

    Sentry: https://sentry.io/privacy/

    Oracle Cloud: https://www.oracle.com/legal/privacy/privacy-policy.html

    Social Platforms: We may have accounts or servers on social media platforms like Discord, Twitter/X, etc. (“Social Platforms”). These are operated by the platform owners, and their data collection is governed by their privacy policies. When you interact with our Social Platforms, we may also collect Personal Data you provide to us (e.g., your username, contact details if you message us).

4. OUR LEGAL BASES FOR PROCESSING YOUR INFORMATION

We process your Personal Data in reliance on the following legal bases (these are particularly relevant for GDPR but good practice globally):

    Your Consent: Where you have provided consent for us to process your Personal Data for a specific purpose (e.g., for optional features, or specific types of marketing communications if you implement them). You may withdraw your consent at any time as described in Section 9.

    Performance of a Contract: When processing your Personal Data is necessary to perform our contract with you, primarily our Terms of Service, such as providing you access to the Game, its features (including multiplayer and User Content sharing), and customer support.

    Our Legitimate Interests: When processing is necessary for our legitimate interests, provided these interests are not overridden by your rights and interests. Our legitimate interests include:

        Operating, maintaining, and improving the Services (e.g., fixing bugs, developing new features).

        Personalizing your experience (e.g., remembering settings).

        Understanding how users interact with the Services to enhance them.

        Ensuring the security and integrity of our Services, preventing fraud, and protecting our users.

        Communicating with you about service-related matters.

        Enforcing our Terms of Service and protecting our legal rights.

        Managing our business operations.

    Compliance with Legal Obligations: When processing is necessary for us to comply with a legal obligation (e.g., responding to lawful requests from authorities, tax obligations).

    Vital Interests: In rare cases, when processing is necessary to protect your vital interests or those of another person (e.g., in an emergency situation).

5. HOW WE USE PERSONAL DATA

We may use Personal Data for the following purposes, based on the legal bases described above:

    To provide, operate, support, and maintain the Services, including enabling core gameplay, multiplayer functionality, User Content creation and sharing, and processing in-app purchases.

    To provide you with customer support and respond to your inquiries.

    To send administrative information to you (e.g., updates to our Terms or this Privacy Policy, service announcements).

    To personalize and improve your experience with the Services.

    To analyze how you and other users interact with our Services for development, improvement, and optimization.

    To monitor, maintain, and improve the stability and security of the Services, including detecting and preventing fraud, unauthorized activity, cheating, or misuse of our Services, and to ensure the security of our IT systems.

    To develop new products, services, and features.

    To comply with legal obligations and legal process, and to protect our rights, privacy, safety, or property, and/or that of our affiliates, you, or other third parties.

    To fulfill any other purpose for which you provide it or with your consent.

    To create anonymous, de-identified, or aggregated datasets (“Aggregated Information”). Such datasets are not Personal Data. We may use Aggregated Information for any purpose, including research, analytics, and improving our Services.

The usage information we collect helps us to improve our Services and to deliver a better and more personalized experience by enabling us to:

    Recognize you when you use the Services.

    Estimate our audience size, demographics, and usage patterns.

    Store your preferences and user settings.

    Understand how well Services features are working and identify issues.

    Identify and correct software defects.

    Prevent fraud and illegal behavior.

6. SHARING AND DISCLOSURE OF PERSONAL DATA

We may share the categories of Personal Data described above in the following circumstances, and unless otherwise required by law, without further notice to you:

    Vendors and Service Providers: With third-party vendors and service providers who perform services on our behalf, such as platform providers (Meta) and multiplayer service providers. These parties are authorized to use your Personal Data only as necessary to provide these services to us and are under contractual obligations to protect it.

    Other Players: Certain Personal Data, such as your platform username, profile picture, and your User Content (custom builds, etc.), will be visible to other players within the Game as part of the multiplayer and social experience. Your voice in voice chat will be audible to other players in your session.

    Business Transfers: If we are involved in a merger, acquisition, financing due diligence, reorganization, bankruptcy, receivership, sale of all or a portion of our assets, or transition of service to another provider (a “Transaction”), your Personal Data may be shared during the diligence process and transferred to a successor or affiliate as part of that Transaction.

    Legal Requirements: If required by law or in the good faith belief that such action is necessary to (i) comply with a legal obligation, subpoena, court order, or lawful requests from public authorities (including to meet national security or law enforcement requirements), (ii) protect and defend our rights or property, (iii) prevent fraud or abuse, (iv) act in urgent circumstances to protect the personal safety of users of the Services or the public, or (v) protect against legal liability.

    Enforcing our Rights: To enforce our Terms of Service or other agreements, including for billing and collection purposes (if applicable).

    With Your Consent: We may disclose your Personal Data for any other purpose with your explicit consent.

We do not "sell" your Personal Data in the traditional sense (i.e., for monetary payment). However, California law (CCPA/CPRA) has a broader definition of "sell" and "share" (for cross-context behavioral advertising).

7. DATA RETENTION, STORAGE, AND INTERNATIONAL TRANSFERS

Storage Location: Information we collect is primarily processed and stored in the United States. If you are accessing the Services from outside the United States, please be aware that your Personal Data will be transferred to, stored, and processed in the United States, where data protection laws may differ from those in your jurisdiction.

Retention Period: We retain your Personal Data for as long as necessary to fulfill the purposes for which it was collected, including to provide the Services, comply with our legal obligations (e.g., for tax and accounting purposes), resolve disputes, enforce our agreements, and for our legitimate business interests (e.g., to improve and develop the Services and prevent fraud).

Aggregated or de-identified data may be retained indefinitely.

Cross-border Data Transfers: By using the Services, you consent to the transfer of your Personal Data to the United States. Where cross-border transfers are necessary (e.g., if we use service providers in other countries), we take steps to ensure that your Personal Data receives an adequate level of protection in the jurisdictions in which we process it, which may include implementing Standard Contractual Clauses (SCCs) or relying on other lawful transfer mechanisms.

8. DATA SECURITY

We implement reasonable administrative, technical, and physical security measures designed to protect your Personal Data from accidental loss and from unauthorized access, use, alteration, and disclosure. We primarily rely on the security measures of our platform provider (Meta) and our chosen third-party service providers who employ industry-standard security practices.

However, the transmission of information via the internet and VR platforms is not completely secure. Although we strive to protect your Personal Data, we cannot guarantee its absolute security. Any transmission of Personal Data is at your own risk. We are not responsible for the circumvention of any privacy settings or security measures contained on the Services or on third-party platforms.

9. YOUR RIGHTS AND CHOICES

You have certain rights and choices regarding your Personal Data.

Accessing and Updating Your Information:

Much of your profile information (e.g., username, profile picture) is managed through your platform account (e.g., Meta account). Please refer to your platform provider's settings to manage this information.

For other Personal Data we hold, you can request access or correction by contacting us at hello@scenexr.com.

Deleting Your Personal Data:

You can request the deletion of your Personal Data that we hold by contacting us at hello@scenexr.com. We may also provide an in-Game option to request account data deletion.

Please note that this is not an absolute right. We may need to retain certain information for legal or legitimate business purposes, such as to complete transactions, prevent fraud, resolve disputes, enforce our agreements, or comply with our legal obligations. We will inform you if we cannot fulfill your request entirely for such reasons.

Opting Out of Communications:

    Promotional Emails (if any): If we send promotional emails, you can opt-out by following the unsubscribe instructions in those emails.

    Service-Related Communications: You generally cannot opt-out of non-promotional, service-related communications (e.g., updates to Terms, security alerts), as they are necessary for your use of the Services.

Cookies (for Site, if applicable):

    Most web browsers allow you to control cookies through their settings. You can set your browser to refuse all or some browser cookies, or to alert you when cookies are being sent. If you disable or refuse cookies, please note that some parts of the Site (if any) may be inaccessible or not function properly.

Managing In-Game Settings:

    The Game may offer settings to control certain features or data sharing (e.g., muting voice chat, privacy settings for User Content visibility if applicable).

Rights for Residents of Certain Jurisdictions:

California Residents (CCPA/CPRA): If you are a California resident, you have specific rights regarding your Personal Data, including:

    Right to Know/Access: To request information about the categories and specific pieces of Personal Data we have collected about you, the categories of sources, the purposes for collection, and the categories of third parties with whom we have shared it.

    Right to Delete: To request the deletion of your Personal Data, subject to certain exceptions.

    Right to Correct: To request correction of inaccurate Personal Data.

    Right to Limit Use of Sensitive Personal Information (if applicable): If we collect sensitive personal information (as defined by CCPA/CPRA) for purposes beyond what is necessary to provide the services, you may have a right to limit its use.

    Right to Non-Discrimination: We will not discriminate against you for exercising your CCPA/CPRA rights.

To exercise these rights, please contact us at hello@scenexr.com. We will verify your request using the information associated with your account. You may also designate an authorized agent to make a request on your behalf.

European Economic Area (EEA), United Kingdom (UK), and Switzerland Residents (GDPR/UK GDPR): If you are a resident of these regions, you have rights including:

    The right to access, rectify, or erase your Personal Data.

    The right to restrict or object to processing.

    The right to data portability.

    The right to withdraw consent (where processing is based on consent).

    The right to lodge a complaint with a supervisory authority.

To exercise these rights, please contact us at hello@scenexr.com.

We will respond to your requests within the timeframes required by applicable law.

10. CHANGES TO THIS PRIVACY POLICY

We may update this Privacy Policy from time to time to reflect changes in our practices, the Services, or applicable law. If we make material changes, we will notify you by posting the updated policy within the Game, on our Site (if any), or by other means (such as email if we have your address) as required by law, prior to the change becoming effective. We will also update the “Last Updated” date at the top of this policy.

Your continued use of the Services after any such changes take effect constitutes your acknowledgment of the revised Privacy Policy. We encourage you to review this Privacy Policy periodically.

11. CONTACT US

If you have any questions, comments, or concerns about this Privacy Policy or our data practices, please contact us at:

ANY Reality LLC

Email: hello@scenexr.com

San Diego, California, USA
"""

const DEFAULT_TOS_TEXT := """
TERMS OF SERVICE FOR SCENEXR

Last Updated: September 4, 2025

Welcome! These Terms of Service govern your use of SceneXR (the “Game”). The Game is a copyrighted work belonging to ANY Reality LLC (“Company”, “us”, “our”, and “we”). These Terms of Service, together with our Privacy Policy (which can be found at scenexr.com/privacy-policy), (collectively, the “Terms”) set forth the legally binding terms and conditions that govern your use of the Game. The Game is licensed, not sold to you.

BY CLICKING THE “AGREE” BUTTON IN THE GAME, INSTALLING, DOWNLOADING, ACCESSING, OR OTHERWISE USING THE GAME, YOU (A) ACKNOWLEDGE THAT YOU HAVE READ AND UNDERSTAND THIS AGREEMENT; (B) REPRESENT THAT YOU ARE EITHER (i) OF LEGAL AGE TO ENTER INTO A BINDING AGREEMENT (18 YEARS OF AGE OR OLDER IN CALIFORNIA) OR (ii) YOU ARE OVER THE AGE OF 13 AND HAVE THE CONSENT AND ARE UNDER THE SUPERVISION OF YOUR PARENT OR LEGAL GUARDIAN WHO HAS AGREED TO THESE TERMS; AND (C) ACCEPT THIS AGREEMENT AND AGREE THAT YOU ARE LEGALLY BOUND BY ITS TERMS. IF YOU DO NOT AGREE TO THESE TERMS, DO NOT USE THE GAME AND DELETE IT FROM YOUR DEVICE.

1. Access to the Game.

1.1 Eligibility.

Only persons meeting the following requirements may use the Game:

    Persons who are at or above the legal age of majority in their jurisdiction (18 years old in California and most states) who agree to be bound by all of these Terms; or

    Persons who are between the ages of 13 and the legal age of majority in their jurisdiction, who have the consent and are under the supervision of their parent or legal guardian, and whose parent or legal guardian has read and agreed to these Terms and agrees to be responsible for the child's use of the Game; or

    Persons who are between the ages of 10 and 12 years old who are accessing the Game through a Meta account that is set up and managed by their parent or legal guardian (Parent-Managed Account) and provided that their parent or legal guardian has reviewed and accepted the account request for their child to download and play the Game, and has agreed to these Terms on behalf of their child. You can find more information about Parent-Managed Meta accounts here

1.2 License.

Subject to these Terms, your acceptance of and compliance with the same, and provided that you meet the eligibility requirements in Section 1.1 above, Company grants you a limited non-transferable, non-exclusive, revocable, limited license to download, install and use the Game for your personal, non-commercial use on a single VR headset or other compatible device owned or otherwise controlled by you ("Device") strictly in accordance with the Game's documentation and these Terms.

1.3 Certain Restrictions.

The rights granted to you in these Terms are subject to the following restrictions. You shall not:

    copy, reproduce, distribute, republish, download, display, post or otherwise transmit the Game in any form or by any means, except as expressly permitted by this license;

    license, sell, rent, lease, transfer, assign, distribute, publish, host, exploit or otherwise make available the Game, or any features or functionality of the Game, to any third party for any reason, including by making the Game available on a network where it is capable of being accessed by more than one device at any time;

    modify, translate, adapt, make derivative works or improvements of the Game, whether or not patentable;

    disassemble, decode, reverse compile or reverse engineer or otherwise attempt to derive or gain access to the source code of any part of the Game;

    access the Game in order to build a similar or competitive product, game or service;

    remove, delete, alter, or obscure any trademarks or any copyright, trademark, patent, or other intellectual property or proprietary rights notices from the Game, including any copy thereof; and

    remove, disable, circumvent or otherwise create or implement any workaround to any copy protection, rights management, or security features in or protecting the Game.

Unless otherwise indicated, any future release, update, patch, DLC, or other addition to functionality of the Game shall be subject to these Terms. All copyright and other proprietary notices on the Game (or on any content displayed on the Game) must be retained on all copies thereof.

1.4 Modification.

Company reserves the right, at any time, to modify, suspend, or discontinue the Game (in whole or in part) with or without notice to you. You agree that ANY Reality LLC will not be liable to you or to any third party for any modification, suspension, or discontinuation of the Game or any part thereof.

1.5 No Support or Maintenance.

You acknowledge and agree that Company will have no obligation to provide you with any support or maintenance in connection with the Game, unless otherwise required by applicable law or explicitly stated by Company.

1.6 Ownership; Reservation of Rights.

You acknowledge and agree that the Game is provided under license, and not sold, to you. You do not acquire any ownership interest in the Game under these Terms, or any other rights thereto other than to use the Game in accordance with these Terms. ANY Reality LLC and its licensors and Game providers reserve and retain their entire right, title, and interest in and to the Game, including all copyrights, trademarks, and other intellectual property rights therein or relating thereto, except as expressly granted to you in these Terms. Neither these Terms (nor your access to the Game) transfers to you or any third party any rights, title or interest in or to such intellectual property rights, except for the limited access rights expressly set forth in Section 1.2. ANY Reality LLC and its suppliers reserve all rights not granted in these Terms. There are no implied licenses granted under these Terms.

2. Acceptable Use and Information Submitted Through the Game (and Outside Platforms)

2.1 User Content.

“User Content” means any and all information and content of any kind that you or any other user submits, creates, shares, uploads, records, or transmits to, or uses with, the Game. This includes, but is not to, custom builds, map modifications, 3D creations, artwork, text communications, voice communications (e.g., via in-game voice chat, which may be recorded for moderation and safety purposes as detailed in our Privacy Policy), player-generated levels, and any submissions to any group, server or other manner of forum on social media organized by or associated with Company including without limitation, any official Discord server, subreddit, and any of our other social accounts or pages (“Outside Platform(s)”). Your submission of User Content is governed by this Agreement and the Company Privacy Policy if through the Game, or if through an Outside Platform, by the terms and policies of the applicable platform, provided that your User Content must, in either case, always comply with the terms of this Section 2. By submitting, creating, or sharing User Content through the Game or Outside Platform, you make the following representations, warranties and agreements:

    You meet the eligibility requirements in Section 1.1 above;

    You agree that you are solely responsible for, and you assume all risks associated with your User Content, including any reliance on its accuracy, completeness or usefulness by others, or any disclosure of your User Content that personally identifies you or any third party;

    You consent to our collection, use, and disclosure of your personal information as outlined in the Privacy Policy, including potential recording and moderation of voice communications;

    To the extent that you submit information that personally identifies or is otherwise of or about a third party (“Third Party Information”) through the Game or Outside Platform, you represent that all such Third Party Information is of persons who are at least 18 years of age (or, if younger, that you have obtained all necessary parental consents), and that you have validly obtained all consents and provided all notices required by applicable law for the submission, disclosure and use by us of the Third Party Information;

    All information or material that you submit through the Game or Outside Platform is true, accurate and complete to your knowledge, and you will maintain and update such information and materials as needed such that it remains true, accurate and complete;

    You hereby represent and warrant that your User Content on all Outside Platforms is in full compliance with all terms, rules and guidelines of the applicable platforms;

    You hereby represent and warrant that your User Content does not violate our Acceptable Use Policy (defined in Section 2.3).

You may not represent or imply to others that your User Content is in any way provided, sponsored or endorsed by Company. Because you alone are responsible for your User Content, you may expose yourself to liability if, for example, your User Content violates the Acceptable Use Policy. Company is not obligated to backup any User Content, and your User Content may be deleted at any time without prior notice. You are solely responsible for creating and maintaining your own backup copies of your User Content if you desire.

2.2 License to User Content.

You hereby grant (and you represent and warrant that you have the right to grant) to ANY Reality LLC an irrevocable, nonexclusive, royalty-free and fully paid, worldwide license to reproduce, distribute, publicly display and perform, prepare derivative works of, incorporate into other works, and otherwise use and exploit your User Content, and to grant sublicenses of the foregoing rights, for the purposes of including your User Content in the Game, operating and improving the Game, providing Game-related services, moderating content, ensuring safety, and promoting the Game or ANY Reality LLC (e.g., by using screenshots or clips of your creations in marketing materials). You hereby irrevocably waive (and agree to cause to be waived) any claims and assertions of moral rights or attribution with respect to your User Content to the fullest extent permitted by applicable law.

2.3 Acceptable Use Policy.

The following terms constitute our “Acceptable Use Policy”:

    You agree not to use the Game to submit, collect, upload, transmit, display, or distribute any User Content that (i) violates any third-party right, including any copyright, trademark, patent, trade secret, moral right, privacy right, right of publicity, or any other intellectual property or proprietary right; (ii) is unlawful, harassing, abusive, threatening, harmful, invasive of another’s privacy, vulgar, defamatory, false, intentionally misleading, trade libelous, pornographic, obscene, patently offensive (e.g., material that promotes racism, bigotry, hatred, or physical harm of any kind against any group or individual), or otherwise objectionable in Company’s sole discretion; (iii) is harmful to minors in any way; or (iv) is in violation of any law, regulation, or obligations or restrictions imposed by any third party.

    In addition, you agree not to: (i) upload, transmit, or distribute to or through the Game any computer viruses, worms, or any software intended to damage or alter a computer system or data; (ii) send through the Game unsolicited or unauthorized advertising, promotional materials, junk mail, spam, chain letters, pyramid schemes, or any other form of duplicative or unsolicited messages, whether commercial or otherwise; (iii) use the Game to harvest, collect, gather or assemble information or data regarding other users, including email addresses or voice data, without their and our consent; (iv) interfere with, disrupt, or create an undue burden on servers or networks connected to the Game, or violate the regulations, policies or procedures of such networks; (v) attempt to hack or otherwise gain unauthorized access to the Game (or to other computer systems or networks connected to or used together with the Game), whether through password mining or any other means; (vi) harass, bully, or interfere with any other user’s use and enjoyment of the Game, including through voice chat or by creating offensive User Content; (vii) circumvent Game rules, exploit bugs or glitches, or otherwise cheat during or in connection with playing the Game; (viii) use software or automated agents or scripts to produce multiple accounts on the Game, or to generate automated searches, requests, or queries to (or to strip, scrape, or mine data from) the Game (provided, however, that we conditionally grant to the operators of public search engines revocable permission to use spiders to copy materials from the Game for the sole purpose of and solely to the extent necessary for creating publicly available searchable indices of the materials, but not caches or archives of such materials, subject to the parameters set forth in our robots.txt file, if any).

2.4 Enforcement.

We reserve the right (but have no obligation) to review any User Content, and to investigate and/or take appropriate action against you in our sole discretion if you violate the Acceptable Use Policy or any other provision of these Terms or otherwise create liability for us or any other person. Such action may include removing or modifying your User Content, suspending or terminating your access to the Game in accordance with Section 14, and/or reporting you to law enforcement authorities. This may include reviewing recorded voice communications if a report is made or if suspicious activity is detected, as further described in our Privacy Policy.

2.5 Feedback.

If you provide ANY Reality LLC with any feedback, information, ideas, comments or suggestions of any kind, including but not to feedback related to the Game or other Company projects (collectively “Feedback”), you hereby assign to Company all rights in such Feedback and agree that Company shall have the right to use and fully exploit such Feedback and related information in any manner it deems appropriate. Company will treat any Feedback you provide to Company as non-confidential and non-proprietary. You agree that you will not submit to Company any information or ideas that you consider to be confidential or proprietary.

3. VR HEALTH AND SAFETY WARNINGS

YOUR HEALTH AND SAFETY ARE IMPORTANT TO US. USING VIRTUAL REALITY (VR) APPLICATIONS CAN CAUSE MOTION SICKNESS, DISORIENTATION, EYESTRAIN, OR OTHER DISCOMFORT OR HEALTH ISSUES. PLEASE READ AND FOLLOW ALL HEALTH AND SAFETY WARNINGS PROVIDED BY YOUR VR HEADSET MANUFACTURER.

BY USING THE GAME, YOU ACKNOWLEDGE AND AGREE TO THE FOLLOWING:

    Consult a Doctor: Consult with your doctor before using the Game if you have pre-existing serious medical conditions (such as a heart condition, seizure disorder, or binocular vision abnormalities), conditions that affect your ability to safely perform physical activities, psychiatric conditions (such as anxiety disorders or post-traumatic stress disorder), or if you are pregnant or elderly. Do not use the Game if you are sick, fatigued, under the influence of intoxicants/drugs, or are not feeling generally well, as it may exacerbate your condition.

    Safe Environment: Always be aware of your surroundings when playing in VR. Ensure your play area is clear of people, pets, furniture, and other objects that could cause injury or be damaged. It is recommended to remain seated or use a stationary play style unless the Game specifically requires room-scale activity and you have adequate clear space. Use the guardian system of your VR headset.

    Take Breaks: Extended VR use can cause discomfort. Take regular breaks (e.g., 10-15 minutes every 30-60 minutes of play) even if you don’t think you need them. If you experience nausea, dizziness, eye strain, or any other discomfort, stop playing immediately and rest until you feel better.

    Motion Sickness: Some people may experience motion sickness, dizziness, disorientation, blurred vision, or other discomfort while using VR. If you experience any of these symptoms, stop playing immediately. Symptoms can persist after you stop playing. Gradually acclimate yourself to VR experiences.

    Seizures: Some people (about 1 in 4000) may experience severe dizziness, seizures, epileptic seizures or blackouts triggered by light flashes or patterns, and this may occur while they are watching TV, playing video games or experiencing virtual reality, even if they have never had a seizure or blackout before or have no history of seizures or epilepsy. Such seizures are more common in children and young people. Anyone who has had a seizure, loss of awareness, or other symptom linked to an epileptic condition should see a doctor before playing the Game. Discontinue use immediately and consult a doctor if you experience any of these symptoms.

    Repetitive Stress Injuries: Playing video games, including VR games, can make your muscles, joints, skin or eyes hurt. To avoid problems such as tendinitis, carpal tunnel syndrome, skin irritation or eyestrain:

        Avoid excessive play. Parents or guardians should monitor their children for appropriate play.

        Take a 10 to 15 minute break every hour, even if you don't think you need it.

        If your hands, wrists, arms or eyes become tired or sore while playing, or if you feel symptoms such as tingling, numbness, burning or stiffness, stop and rest for several hours before playing again.

        If you continue to have any of the above symptoms or other discomfort during or after play, stop playing and see a doctor.

    Children's Use: Children using VR should be supervised by an adult. The VR headset manufacturer (e.g., Meta) has specific age recommendations and safety guidelines for children, which must be followed. Parents and guardians are responsible for ensuring their child complies with these guidelines and these Terms.

    Content Sensitivity: Some game content or user-generated content may be intense or startling for some users. Exercise discretion.

FAILURE TO FOLLOW THESE SAFETY GUIDELINES AND THOSE OF YOUR VR HEADSET MANUFACTURER MAY RESULT IN INJURY TO YOURSELF OR OTHERS, OR DAMAGE TO YOUR PROPERTY OR THE DEVICE. YOU AGREE THAT YOUR USE OF THE GAME IS AT YOUR SOLE RISK.

4. Device Requirements.

The Game can only be used via certain VR headsets and compatible devices. A list of supported devices may be provided on the ANY Reality LLC website (if applicable) and/or the third-party application marketplaces ("Marketplaces") like the Meta Quest Store where the application can be downloaded. Your Device must also meet the minimum system requirements on the ANY Reality LLC Website and/or the Marketplaces in connection with the Game. You are responsible for ensuring your Device meets these requirements.

5. Updates.

Company may from time to time in its sole discretion develop and provide Game updates, which may include upgrades, bug fixes, patches, other error corrections, and/or new features (collectively, including related documentation, "Updates"). Updates may also modify or delete in their entirety certain features and functionality. You agree that Company has no obligation to provide any Updates or to continue to provide or enable any particular features or functionality. Based on your Device settings when your Device is connected to the internet either:

    the Game will automatically download and install all available Updates; or

    you may receive notice of or be prompted to download and install available Updates.

You will promptly download and install all Updates and acknowledge and agree that the Game or portions thereof may not properly operate should you fail to do so. You further agree that all Updates will be deemed part of the Game and be subject to these Terms.

6. Free Features and Trials.

(If applicable: e.g., "Upon downloading the Game, users may have access to certain features of the Game (“Free Features”) or a trial period. Company may add, remove, modify or otherwise change the free features or trial conditions at any time with or without notice to you.")

(If your game is paid upfront with no free component, you can remove or modify this section to state that purchase is required.)

7. Making Purchases Through the Game.

Purchases through our Game, if any (such as for the Game itself or for Digital Items as defined below), are primarily processed by the Marketplace where you download the Game (e.g., the Meta Quest Store) and are governed by the Terms of Sale of the relevant Marketplace. Your purchase will be to your account with the Marketplace. You understand and agree that you cannot transfer purchases from one account to another. You understand and agree that we are not responsible for any problems or losses associated with your Marketplace account, including without limitation, problems transferring purchases from one device to another, or restoring purchases from a lost or damaged device to a different device. We reserve the right to revise pricing for features or Digital Items offered for purchase through the Game at any time, subject to the terms of the applicable Marketplace.

8. Digital Items.

(This section is relevant for IAP. If you have no IAP, remove or state "The Game does not currently offer Digital Items for purchase.")

8.1 Nature of Digital Items.

The Game may include virtual currencies such as virtual tokens or coins, or make virtual items, resources, tools, or services available for purchase or earning within the Game (collectively “Digital Items"). If you meet the eligibility requirements (including age and parental consent if applicable), you may be able to buy or acquire Digital Items. You agree that once purchased or acquired, Digital Items have no monetary value and can never be exchanged for real money, real goods, or real services from us or anyone else. You also agree that you will only obtain Digital Items from us or through authorized means within the Game, and not from any third party. You agree that Digital Items are not transferrable to anyone else, and you will not transfer or attempt to transfer any Digital Items to anyone else, unless expressly permitted by the Game's functionality (e.g., in-game gifting systems, if any).

8.2 License to Digital Items.

You do not own Digital Items but instead you purchase or acquire a limited, personal, revocable, non-transferable, non-sublicensable license to use them within the Game. Any balance of Digital Items does not reflect any stored value and does not constitute a personal property right.

8.3 Sales are Final.

You agree that all sales by us or the applicable Marketplace to you of Digital Items are final and that we will not refund any transaction once it has been made, except as required by applicable law or the policies of the Marketplace. If you reside in a jurisdiction with mandatory withdrawal rights for distance purchases, please note that when you purchase a license to use Digital Items from us, you acknowledge and agree that we will begin the provision of the Digital Items to you promptly once your purchase is complete, and therefore your right of withdrawal may be lost at this point. For the purposes of this Section 8.3, a "purchase" is complete at the time our servers (or the Marketplace's servers) validate your purchase and the applicable Digital Items are successfully credited to your account.

8.4 Risk of Loss & Account Linkage.

The Digital Items that you purchase or acquire will be to your Game account, which may be tied to your account with the Marketplace where you make the purchase. You understand and agree that we are not responsible for any problems or losses associated with your Marketplace account or Game account, including without limitation, problems transferring Digital Items from one device to another, restoring Digital Items from a lost or damaged device to a different device, or any other losses of Digital Items. The risk of loss of Digital Items is transferred to you upon completion of the purchase or acquisition as described in Section 8.3 above.

8.5 Regulation of Digital Items.

We reserve the right, in our sole discretion, to control, regulate, change, or remove any Digital Items with or without notice and without any liability to you.

8.6 Pricing and Limits.

We may revise the pricing for Digital Items offered through the Game at any time. We may limit the total amount of Digital Items that may be purchased at any one time, and/or limit the total amount of Digital Items that may be held in your account in the aggregate. You are only allowed to purchase or acquire Digital Items from us or our authorized partners through the Game, and not in any other way.

8.7 Loss upon Suspension/Termination.

Without limiting Section 8.5, if we suspend or terminate your account or access to the Game in accordance with these Terms, you will lose any Digital Items that you may have accumulated, and we will not compensate you for this loss or make any refund to you.

9. Indemnification.

You agree to indemnify, defend, and hold ANY Reality LLC (and its officers, employees, directors, affiliates, agents, successors, and assigns) harmless, from and against any and all losses, damages, liabilities, deficiencies, claims, actions, judgments, settlements, interest, awards, penalties, fines, costs, or expenses of whatever kind, including reasonable attorneys’ fees, from any claim or demand made by any third party due to or arising out of (a) your use of the Game, (b) your User Content (whenever submitted or created), (c) your violation of these Terms, or (d) your violation of applicable laws or regulations or the rights of a third party. ANY Reality LLC reserves the right, at your expense, to assume the exclusive defense and control of any matter for which you are required to indemnify us, and you agree to cooperate with our defense of these claims. You agree not to settle any matter without the prior written consent of ANY Reality LLC. ANY Reality LLC will use reasonable efforts to notify you of any such claim, action or proceeding upon becoming aware of it.

10. Terms Regarding Third-Party Services.

10.1 Third-Party Services.

The Game may display, include, make available or contain to third-party content, websites, services, or advertisements (collectively, “Third-Party Services”). Such Third-Party Services are not under the control of Company, and Company is not responsible for any Third-Party Services. Company does not assume and will not have any liability or responsibility to you or any other person or entity for any Third-Party Services. Company provides access to these Third-Party Services, if any, only as a convenience to you, and does not review, approve, monitor, endorse, warrant, or make any representations with respect to Third-Party Services. You acknowledge and agree that Company is not responsible for Third-Party Services, including their accuracy, completeness, timeliness, validity, copyright compliance, legality, decency, quality, or any other aspect thereof. You access and use them entirely at your own risk and subject to such third parties' terms and conditions. You should make whatever investigation you feel necessary or appropriate before proceeding with any transaction in connection with such Third-Party Services.

11. Release.

You hereby release and forever discharge ANY Reality LLC (and our officers, employees, agents, successors, and assigns) from, and hereby waive and relinquish, each and every past, present and future dispute, claim, controversy, demand, right, obligation, liability, action and cause of action of every kind and nature (including personal injuries, death, and property damage), that has arisen or arises directly or indirectly out of, or that relates directly or indirectly to, the Game (including any interactions with, or act or omission of, other Game users or any Third-Party Services). IF YOU ARE A CALIFORNIA RESIDENT, YOU HEREBY WAIVE CALIFORNIA CIVIL CODE SECTION 1542 IN CONNECTION WITH THE FOREGOING, WHICH STATES: “A GENERAL RELEASE DOES NOT EXTEND TO CLAIMS THAT THE CREDITOR OR RELEASING PARTY DOES NOT KNOW OR SUSPECT TO EXIST IN HIS OR HER FAVOR AT THE TIME OF EXECUTING THE RELEASE AND THAT, IF KNOWN BY HIM OR HER, WOULD HAVE MATERIALLY AFFECTED HIS OR HER SETTLEMENT WITH THE DEBTOR OR RELEASED PARTY.”

12. Disclaimers.

THE GAME IS PROVIDED TO YOU "AS IS" AND "AS AVAILABLE" AND WITH ALL FAULTS AND DEFECTS WITHOUT WARRANTY OF ANY KIND. TO THE MAXIMUM EXTENT PERMITTED UNDER APPLICABLE LAW, COMPANY, ON ITS OWN BEHALF AND ON BEHALF OF ITS AFFILIATES AND ITS AND THEIR RESPECTIVE LICENSORS AND SERVICE PROVIDERS, EXPRESSLY DISCLAIMS ALL WARRANTIES, WHETHER EXPRESS, IMPLIED, STATUTORY, OR OTHERWISE, WITH RESPECT TO THE GAME, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, QUIET ENJOYMENT AND NON-INFRINGEMENT, AND WARRANTIES THAT MAY ARISE OUT OF COURSE OF DEALING, COURSE OF PERFORMANCE, USAGE, OR TRADE PRACTICE. WITHOUT LIMITATION TO THE FOREGOING, COMPANY PROVIDES NO WARRANTY OR UNDERTAKING, AND MAKES NO REPRESENTATION OF ANY KIND THAT THE GAME WILL MEET YOUR REQUIREMENTS, ACHIEVE ANY INTENDED RESULTS, BE COMPATIBLE, OR WORK WITH ANY OTHER SOFTWARE, GAMES, APPLICATIONS, SYSTEMS, OR SERVICES, OPERATE WITHOUT INTERRUPTION, MEET ANY PERFORMANCE OR RELIABILITY STANDARDS, OR BE ERROR-FREE, ACCURATE, RELIABLE, FREE FROM HARMFUL CODE (SUCH AS VIRUSES), COMPLETE, LEGAL, SAFE, AVAILABLE ON AN UNINTERRUPTED BASIS OR THAT ANY ERRORS OR DEFECTS CAN OR WILL BE CORRECTED.

SOME JURISDICTIONS DO not ALLOW THE EXCLUSION OF OR LIMITATIONS ON IMPLIED WARRANTIES OR THE LIMITATIONS ON THE APPLICABLE STATUTORY RIGHTS OF A CONSUMER, SO SOME OR ALL OF THE ABOVE EXCLUSIONS AND LIMITATIONS MAY NOT APPLY TO YOU.

13. Limitation on Liability.

TO THE FULLEST EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT WILL COMPANY OR ITS AFFILIATES, OR ANY OF ITS OR THEIR RESPECTIVE LICENSORS OR SERVICE PROVIDERS, HAVE ANY LIABILITY ARISING FROM OR RELATED TO YOUR USE OF OR INABILITY TO USE THE GAME FOR:

    PERSONAL INJURY (INCLUDING INJURY RELATED TO VR USE), PROPERTY DAMAGE, LOST PROFITS, COST OF SUBSTITUTE GOODS OR SERVICES, LOSS OF DATA, LOSS OF GOODWILL, BUSINESS INTERRUPTION, COMPUTER OR DEVICE FAILURE OR MALFUNCTION, OR ANY OTHER CONSEQUENTIAL, INCIDENTAL, INDIRECT, EXEMPLARY, SPECIAL, OR PUNITIVE DAMAGES; OR

    DIRECT DAMAGES IN AMOUNTS THAT IN THE AGGREGATE EXCEED THE AMOUNT ACTUALLY PAID BY YOU FOR THE GAME (IF ANY) OR, IF NO AMOUNT WAS PAID, ONE HUNDRED U.S. DOLLARS (USD $100.00).

THE FOREGOING LIMITATIONS WILL APPLY WHETHER SUCH DAMAGES ARISE OUT OF BREACH OF CONTRACT, TORT (INCLUDING NEGLIGENCE), OR OTHERWISE AND REGARDLESS OF WHETHER SUCH DAMAGES WERE FORESEEABLE OR COMPANY WAS ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. SOME JURISDICTIONS DO not ALLOW CERTAIN LIMITATIONS OF LIABILITY SO SOME OR ALL OF THE ABOVE LIMITATIONS OF LIABILITY MAY NOT APPLY TO YOU.

14. Term and Termination.

The term of this Agreement commences when you first download, install, access or use the Game and will continue in effect until terminated by you or Company as set forth in this Section. Subject to this Section, these Terms will remain in full force and effect while you use the Game. We may suspend or terminate your rights to use the Game (including your access and any associated account) at any time for any reason or no reason at our sole discretion, including for any use of the Game in violation of these Terms or if we cease to support the Game. In addition, this Agreement will terminate immediately and automatically without any notice if you violate any of the terms and conditions of this Agreement. Upon termination of your rights under these Terms for any reason, your right to access and use the Game will terminate immediately, and you must immediately cease all use of the Game and delete all copies of the Game from your Device. Company will not have any liability whatsoever to you for any termination of your rights under these Terms, including for the deletion of your information, User Content, or Digital Items. Even after your rights under these Terms are terminated, the provisions herein which by their nature should survive the termination of this agreement, will survive it, including without limitation: Sections 1.3, 1.6, 2, 8.7, 9 through 13, and 15 through 17. Termination of this Agreement will not limit any of Company’s rights or remedies at law or in equity.

15. Copyright Policy and Takedown Requests (DMCA)

15.1 DMCA Notices.

ANY Reality LLC respects the intellectual property rights of others and we ask you to do the same. In connection with our Game, we have adopted and implemented a policy respecting copyright law that provides for the removal of any infringing materials and for the termination, in appropriate circumstances, of users of our Game who are repeat infringers of intellectual property rights, including copyrights. If you are a copyright owner or an agent of a copyright owner and believe that any content in the Game (including User Content) infringes upon your copyrights, you may submit a notification pursuant to the Digital Millennium Copyright Act ("DMCA") by providing our Copyright Agent with the following information in writing (see 17 U.S.C 512(c)(3) for further detail):

    An electronic or physical signature of the person authorized to act on behalf of the owner of the copyright or other right being infringed;

    A description of the copyright-protected work or other intellectual property right that you claim has been infringed;

    A description of the material that you claim is infringing and where it is located in the Game, sufficient for us to locate the material;

    Your address, telephone number, and email address;

    A statement by you that you have a good faith belief that the use of those materials is not authorized by the copyright owner, its agent, or the law; and

    A statement by you that the above information in your notice is accurate and that, under penalty of perjury, you are the copyright or intellectual property owner or authorized to act on the copyright or intellectual property owner’s behalf.

Our designated Copyright Agent to receive DMCA Notices is:

ANY Reality LLC Copyright Agent

Email: hello@scenexr.com

Address: 3826 tomahawk ln san diego ca

You acknowledge that if you fail to comply with all of the requirements of this Section, your DMCA notice may not be valid. Please note that, pursuant to 17 U.S.C. § 512(f), any misrepresentation of material fact (falsities) in a written notification automatically subjects the complaining party to liability for any damages, costs and attorney's fees incurred by us in connection with the written notification and allegation of copyright infringement.

15.2 Counter-Notices.

If you believe that your User Content that was removed (or to which access was disabled) is not infringing, or that you have the authorization from the copyright owner, the copyright owner’s agent, or pursuant to the law, to post and use the material in your User Content, you may send a counter-notice containing the following information to our Copyright Agent:

	Your physical or electronic signature;

	Identification of the content that has been removed or to which access has been disabled and the location at which the content appeared before it was removed or disabled;

	A statement that you have a good faith belief that the content was removed or disabled as a result of mistake or a misidentification of the content; and

	Your name, address, telephone number, and email address, a statement that you consent to the jurisdiction of the federal court in San Diego, California, and a statement that you will accept service of process from the person who provided notification of the alleged infringement.

If a counter-notice is received by the Copyright Agent, Company may send a copy of the counter-notice to the original complaining party informing that person that it may replace the removed content or cease disabling it in 10 business days. Unless the copyright owner files an action seeking a court order against the content provider, member or user, the removed content may be replaced, or access to it restored, in 10 to 14 business days or more after receipt of the counter-notice, at Company’s sole discretion.

15.3 Repeat Infringer Policy.

Company’s intellectual property policy is to: (i) remove or disable access to material that Company believes in good faith, upon notice from an intellectual property rights owner or their agent, is infringing the intellectual property rights of a third party by being made available through the Game; and (ii) in appropriate circumstances, to terminate the accounts of and block access to the Game by any user who repeatedly or egregiously infringes other people’s copyrights or other intellectual property rights.

16. Dispute Resolution (Governing Law, Arbitration, Class Action Waiver)

16.1 Governing Law.

This Agreement is governed by and construed in accordance with the internal laws of the State of California without giving effect to any choice or conflict of law provision or rule that would require or permit the application of the laws of any jurisdiction other than those of the State of California. Any legal suit, action, or proceeding arising out of or related to this Agreement or the Game shall be instituted exclusively in the federal courts of the United States located in the Southern District of California or the courts of the State of California located in San Diego County. You hereby irrevocably submit to the personal jurisdiction of such courts and waive any and all objections to the exercise of jurisdiction over you by such courts and to venue in such courts.

16.2 Arbitration.

(The example had "Waiver of Jury Trial" resolved by a judge. Arbitration is a common alternative for dispute resolution. Decide if you want this. If so, a more detailed arbitration clause is needed. If not, keep the waiver of jury trial or remove if not desired. For now, I will adapt the example's "Waiver of Jury Trial")

WAIVER OF JURY TRIAL. EACH PARTY IRREVOCABLY AND UNCONDITIONALLY WAIVES, TO THE FULLEST EXTENT PERMITTED BY APPLICABLE LAW, ANY RIGHT IT MAY HAVE TO A TRIAL BY JURY IN ANY LEGAL ACTION, PROCEEDING, CAUSE OF ACTION, OR COUNTERCLAIM ARISING OUT OF OR RELATING TO THIS AGREEMENT, INCLUDING ANY EXHIBITS, SCHEDULES, AND APPENDICES ATTACHED TO THIS AGREEMENT, OR THE MATTERS CONTEMPLATED HEREBY.

16.3 Waiver of Class or Consolidated Actions.

ALL CLAIMS AND DISPUTES WITHIN THE SCOPE OF THIS AGREEMENT MUST BE LITIGATED ON AN INDIVIDUAL BASIS AND NOT ON A CLASS BASIS. CLAIMS OF MORE THAN ONE CUSTOMER OR USER CANNOT BE LITIGATED JOINTLY OR CONSOLIDATED WITH THOSE OF ANY OTHER CUSTOMER OR USER. IF, HOWEVER, THIS WAIVER OF CLASS OR CONSOLIDATED ACTIONS IS DEEMED INVALID OR UNENFORCEABLE, NEITHER YOU NOR WE ARE ENTITLED TO ARBITRATION (if arbitration is chosen) AND ALL CLAIMS AND DISPUTES SHALL BE RESOLVED IN A COURT AS SET FORTH IN SECTION 16.1.

16.4 Limitation of Time to File Claims.

ANY CAUSE OF ACTION OR CLAIM YOU MAY HAVE ARISING OUT OF OR RELATING TO THIS AGREEMENT OR THE GAME MUST BE COMMENCED WITHIN ONE (1) YEAR AFTER THE CAUSE OF ACTION ACCRUES; OTHERWISE, SUCH CAUSE OF ACTION OR CLAIM IS PERMANENTLY BARRED.

17. General Provisions

17.1 Changes to Terms.

These Terms are subject to occasional revision. If we make any substantial changes, we may notify you by sending you an e-mail to the last e-mail address you provided to us (if any), and/or by prominently posting notice of the changes within the Game or on our website. You are responsible for providing us with your most current e-mail address. In the event that the last e-mail address that you have provided us is not valid, or for any reason is not capable of delivering to you the notice described above, our dispatch of the e-mail containing such notice will nonetheless constitute effective notice of the changes described in the notice. Any changes to these Terms will be effective upon the earlier of thirty (30) calendar days following our dispatch of an e-mail notice to you (if applicable) or thirty (30) calendar days following our posting of notice of the changes. These changes will be effective immediately for new users of our Game. Continued use of our Game following notice of such changes shall indicate your acknowledgement of such changes and agreement to be bound by the terms and conditions of such changes.

17.2 Export.

The Game may be subject to U.S. export control laws and may be subject to export or import regulations in other countries. You agree not to export, re-export, or transfer, directly or indirectly, any U.S. technical data acquired from Company, or any products utilizing such data, in violation of the United States export laws or regulations. You must comply with all applicable federal laws, regulations, and rules, and complete all required undertakings (including obtaining any necessary export license or other governmental approval), prior to exporting, re-exporting, releasing, or otherwise making the Game available outside the US.

17.3 Electronic Communications.

The communications between you and ANY Reality LLC use electronic means, whether you use the Game or send us emails, or whether Company posts notices on the Game or communicates with you via email. For contractual purposes, you (a) consent to receive communications from Company in an electronic form; and (b) agree that all terms and conditions, agreements, notices, disclosures, and other communications that Company provides to you electronically satisfy any legal requirement that such communications would satisfy if they were to be in a hardcopy writing. The foregoing does not affect your non-waivable statutory rights.

17.4 Severability.

If any provision of this Agreement is illegal or unenforceable under applicable law, the remainder of the provision will be amended to achieve as closely as possible the effect of the original term and all other provisions of this Agreement will continue in full force and effect.

17.5 Waiver.

No failure to exercise, and no delay in exercising, on the part of either party, any right or any power hereunder will operate as a waiver thereof, nor will any single or partial exercise of any right or power hereunder preclude further exercise of that or any other right hereunder.

17.6 Entire Agreement.

These Terms (including the Privacy Policy incorporated herein by reference) constitute the entire agreement between you and us regarding the use of the Game and supersede all prior and contemporaneous understandings, agreements, representations, and warranties, both written and oral, with respect to the Game. Our failure to exercise or enforce any right or provision of these Terms shall not operate as a waiver of such right or provision. The section titles in these Terms are for convenience only and have no legal or contractual effect. The word “including” means “including without limitation”.

17.7 Assignment.

These Terms, and your rights and obligations herein, may not be assigned, subcontracted, delegated, or otherwise transferred by you without Company’s prior written consent, and any attempted assignment, subcontract, delegation, or transfer in violation of the foregoing will be null and void. ANY Reality LLC may freely assign these Terms. The terms and conditions set forth in these Terms shall be binding upon assignees.

17.8 Relationship of the Parties.

Your relationship to Company is that of an independent contractor, and neither party is an agent or partner of the other.

17.9 Copyright/Trademark Information.

Copyright © 2025 ANY Reality LLC. All rights reserved. "SceneXR," "ANY Reality LLC," and all associated logos are trademarks of ANY Reality LLC or its affiliates. All other trademarks, logos and service marks (“Marks”) displayed on the Game are our property or the property of other third parties. You are not permitted to use these Marks without our prior written consent or the consent of such third party which may own the Marks.

17.10 Contact Information:

ANY Reality LLC

Email: hello@scenexr.com

San Diego, California, USA

Return to Homepage
"""

@onready var tos_label: RichTextLabel = get_node_or_null("MarginContainer/VBoxContainer/TabContainer/TOS/TOSLabel")
@onready var privacy_label: RichTextLabel = get_node_or_null("MarginContainer/VBoxContainer/TabContainer/Privacy/PrivacyLabel")
@onready var tab_container: TabContainer = get_node_or_null("MarginContainer/VBoxContainer/TabContainer") as TabContainer
@onready var tos_path_label: Label = get_node_or_null("MarginContainer/VBoxContainer/TOSPath")
@onready var privacy_path_label: Label = get_node_or_null("MarginContainer/VBoxContainer/PrivacyPath")
@onready var status_label: Label = get_node_or_null("MarginContainer/VBoxContainer/StatusLabel")
@onready var reload_button: Button = get_node_or_null("MarginContainer/VBoxContainer/Buttons/ReloadButton")
@onready var accept_button: Button = get_node_or_null("MarginContainer/VBoxContainer/AcceptRow/AcceptButton")

var _hold_active := false
var _hold_elapsed := 0.0
var _phase: String = "tos"  # "tos" -> "privacy"


func _ready() -> void:
	set_process(false)
	_update_path_labels()
	if reload_button:
		reload_button.pressed.connect(_on_reload_pressed)
	if accept_button:
		accept_button.button_down.connect(_on_accept_down)
		accept_button.button_up.connect(_on_accept_up)
	_reset_hold()
	load_documents()
	_set_ready_status()


func _process(delta: float) -> void:
	if not _hold_active:
		return
	_hold_elapsed += delta
	_update_hold_ui()
	if _hold_elapsed >= required_hold_time:
		_complete_accept()


func load_documents() -> void:
	# Always ship embedded text so builds don't depend on external .md files.
	var tos_text := DEFAULT_TOS_TEXT
	var privacy_text := DEFAULT_PRIVACY_TEXT
	var file_tos := _load_markdown_text(tos_path)
	var file_priv := _load_markdown_text(privacy_path)
	if not file_tos.is_empty():
		tos_text = file_tos
	if not file_priv.is_empty():
		privacy_text = file_priv
	_set_label_text(tos_label, tos_text, "Terms of Service", tos_path)
	_set_label_text(privacy_label, privacy_text, "Privacy Policy", privacy_path)
	if status_label:
		status_label.text = "Loaded legal documents (embedded)"


func _on_reload_pressed() -> void:
	load_documents()


func _on_accept_down() -> void:
	if _hold_active:
		return
	_hold_active = true
	_hold_elapsed = 0.0
	set_process(true)
	if status_label:
		status_label.text = "Holding to accept %s..." % _current_target_label()
	_update_hold_ui()


func _on_accept_up() -> void:
	if _hold_active:
		_reset_hold()
		if status_label:
			status_label.text = "Hold cancelled"


func _complete_accept() -> void:
	_hold_active = false
	set_process(false)
	_hold_elapsed = required_hold_time
	_update_hold_ui()
	if _phase == "tos":
		_phase = "privacy"
		_hold_elapsed = 0.0
		_update_hold_ui()
		_focus_privacy_tab()
		if status_label:
			status_label.text = "TOS accepted. Now hold to accept Privacy."
		return
	if status_label:
		status_label.text = "TOS and Privacy accepted"
	emit_signal("accepted")


func _reset_hold() -> void:
	_hold_active = false
	_hold_elapsed = 0.0
	set_process(false)
	_update_hold_ui()


func _update_hold_ui() -> void:
	var pct: float = clamp(_hold_elapsed / required_hold_time, 0.0, 1.0) * 100.0
	if accept_button:
		accept_button.text = "Hold A/X/Space to accept %s (%.0f%%)" % [_current_target_label(), pct]


func _update_path_labels() -> void:
	if tos_path_label:
		tos_path_label.text = "TOS: %s" % tos_path
	if privacy_path_label:
		privacy_path_label.text = "Privacy: %s" % privacy_path


func _set_label_text(label: RichTextLabel, text: String, fallback_title: String, path: String) -> void:
	if not label:
		return
	var content := text
	if content.is_empty():
		content = "[b]%s[/b]\nNo content found at %s" % [fallback_title, path]
	label.clear()
	label.append_text(_markdown_to_bbcode(content))
	label.scroll_to_line(0)


func _load_markdown_text(path: String) -> String:
	if path.is_empty():
		return ""
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		return file.get_as_text()
	return ""


func _markdown_to_bbcode(text: String) -> String:
	var lines := text.split("\n")
	var converted: PackedStringArray = []
	for line in lines:
		if line.begins_with("### "):
			converted.append("[b]" + line.substr(4) + "[/b]")
		elif line.begins_with("## "):
			converted.append("[b]" + line.substr(3) + "[/b]")
		elif line.begins_with("# "):
			converted.append("[b]" + line.substr(2) + "[/b]")
		elif line.begins_with("- "):
			converted.append("• " + line.substr(2))
		else:
			converted.append(line)
	return "\n".join(converted)


func _unhandled_input(event: InputEvent) -> void:
	# Desktop convenience: hold Space to accept.
	if event is InputEventKey and event.keycode == KEY_SPACE:
		if event.is_pressed() and not event.is_echo():
			_on_accept_down()
		elif not event.is_pressed():
			_on_accept_up()
	elif event is InputEventJoypadButton and (event.button_index == JOY_BUTTON_A or event.button_index == JOY_BUTTON_X):
		if event.is_pressed():
			_on_accept_down()
		else:
			_on_accept_up()


func begin_accept_hold() -> void:
	_on_accept_down()


func end_accept_hold() -> void:
	_on_accept_up()


func _set_ready_status() -> void:
	if status_label:
		status_label.text = "Hold A/X (VR) or Space (desktop) to accept TOS, then Privacy"


func _current_target_label() -> String:
	return "TOS" if _phase == "tos" else "Privacy"


func _focus_privacy_tab() -> void:
	if tab_container and tab_container.get_tab_count() >= 2:
		tab_container.current_tab = 1
