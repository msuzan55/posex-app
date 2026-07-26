/// Maps push [notification_type] values to Dashboard `navigateToPage` targets.
String pageForNotificationType(String notificationType) {
  switch (notificationType.trim()) {
    case 'sales':
    case 'edited_bills':
    case 'exchange_tokens':
    case 'refunds':
    case 'daily_totals':
      return 'reports';
    case 'employee_clock':
    case 'new_employees':
    case 'employee_loans':
    case 'employee_dayoffs':
    case 'salary_paid':
      return 'employees';
    case 'expenses':
      return 'expenses';
    case 'supplier_bills':
    case 'new_suppliers':
      return 'suppliers';
    case 'cash_register_closed':
    case 'cash_register_opened':
      return 'cashRegistry';
    case 'new_customers':
    case 'credit_payments':
      return 'customers';
    case 'held_bills':
      return 'bills';
    default:
      return 'dashboard';
  }
}
