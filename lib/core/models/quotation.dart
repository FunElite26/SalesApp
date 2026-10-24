// lib/core/models/quotation.dart

import 'supplementary_item.dart';

class LineItem {
  final String description;
  final String? hsnSac;
  final double qty;
  final double freeQty;
  final double gstPercent;
  final String uom;
  final double unitPrice; // item_rate
  final double discPercent;
  final double total; // amount
  final String? modelId;
  final String? productId;

  const LineItem({
    required this.description,
    this.hsnSac,
    required this.qty,
    this.freeQty = 0,
    this.gstPercent = 18.0,
    this.uom = 'NOS',
    required this.unitPrice,
    this.discPercent = 0,
    required this.total,
    this.modelId,
    this.productId,
  });

  factory LineItem.fromJson(Map<String, dynamic> json) {
    final q = (json['qty'] as num? ?? 0).toDouble();
    final rate = (json['unit_price'] as num? ?? json['item_rate'] as num? ?? 0).toDouble();
    final disc = (json['disc_percent'] as num? ?? 0).toDouble();
    final defaultTotal = q * rate * (1 - disc / 100);
    return LineItem(
      description: json['description'] as String? ?? '',
      hsnSac: json['hsn_sac'] as String?,
      qty: q,
      freeQty: (json['free_qty'] as num? ?? 0).toDouble(),
      gstPercent: (json['gst_percent'] as num? ?? json['gst_rate'] as num? ?? 18.0).toDouble(),
      uom: json['uom'] as String? ?? 'NOS',
      unitPrice: rate,
      discPercent: disc,
      total: (json['total'] as num? ?? json['amount'] as num? ?? defaultTotal).toDouble(),
      modelId: json['model_id'] as String? ?? json['modelId'] as String?,
      productId: json['product_id'] as String? ?? json['productId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'description': description,
    'hsn_sac': hsnSac,
    'qty': qty,
    'free_qty': freeQty,
    'gst_percent': gstPercent,
    'uom': uom,
    'unit_price': unitPrice,
    'disc_percent': discPercent,
    'total': total,
    if (modelId != null) 'model_id': modelId,
    if (productId != null) 'product_id': productId,
  };

  LineItem copyWith({
    String? description,
    String? hsnSac,
    double? qty,
    double? freeQty,
    double? gstPercent,
    String? uom,
    double? unitPrice,
    double? discPercent,
    String? modelId,
    String? productId,
  }) {
    final newQty = qty ?? this.qty;
    final newPrice = unitPrice ?? this.unitPrice;
    final newDisc = discPercent ?? this.discPercent;
    return LineItem(
      description: description ?? this.description,
      hsnSac: hsnSac ?? this.hsnSac,
      qty: newQty,
      freeQty: freeQty ?? this.freeQty,
      gstPercent: gstPercent ?? this.gstPercent,
      uom: uom ?? this.uom,
      unitPrice: newPrice,
      discPercent: newDisc,
      total: newQty * newPrice * (1 - newDisc / 100),
      modelId: modelId ?? this.modelId,
      productId: productId ?? this.productId,
    );
  }
}

enum QuotationStatus {
  draft,
  pendingApproval,
  confirmed,
  rejected;

  static QuotationStatus fromString(String value) {
    switch (value) {
      case 'draft':
        return QuotationStatus.draft;
      case 'pending_approval':
      case 'pendingApproval':
        return QuotationStatus.pendingApproval;
      case 'confirmed':
        return QuotationStatus.confirmed;
      case 'rejected':
        return QuotationStatus.rejected;
      default:
        return QuotationStatus.draft;
    }
  }

  String get dbValue {
    switch (this) {
      case QuotationStatus.draft:
        return 'draft';
      case QuotationStatus.pendingApproval:
        return 'pending_approval';
      case QuotationStatus.confirmed:
        return 'confirmed';
      case QuotationStatus.rejected:
        return 'rejected';
    }
  }

  String get displayName {
    switch (this) {
      case QuotationStatus.draft:
        return 'Draft';
      case QuotationStatus.pendingApproval:
        return 'Pending Approval';
      case QuotationStatus.confirmed:
        return 'Confirmed';
      case QuotationStatus.rejected:
        return 'Rejected';
    }
  }
}

class Quotation {
  final String id;
  final String pipelineId;
  final String quotationNumber;
  final String productId;
  final List<LineItem> lineItems;
  final Map<String, dynamic> productSpecs;
  final double subtotal;
  final double cgstRate;
  final double sgstRate;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double grandTotal;
  final String? termsText;
  final String? pdfUrl;
  final String? confirmedBy;
  final DateTime? confirmedAt;
  final QuotationStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  // New Indian GST Form Fields
  final String? salesOrderNo;
  final DateTime? orderDate;
  final String? billType;
  final String? placeOfSupply;
  final double? distance;
  final String? grLrNo;
  final String? destination;
  
  final String? customerName;
  final String? billingAddress;
  final String? customerGstin;
  final String? customerPhone;
  final String? partyContactPerson;

  final String? shippingName;
  final String? shippingAddress;
  final int? stateCode;
  final String? salesman;
  final String? remarks;

  final String? leadId;
  final int revision;
  final List<Map<String, dynamic>>? paymentTerms;
  final List<SupplementaryItem>? supplementaryTerms;
  final double supplementarySubtotal;

  const Quotation({
    required this.id,
    required this.pipelineId,
    required this.quotationNumber,
    required this.productId,
    required this.lineItems,
    required this.productSpecs,
    required this.subtotal,
    required this.cgstRate,
    required this.sgstRate,
    required this.cgstAmount,
    required this.sgstAmount,
    this.igstAmount = 0.0,
    required this.grandTotal,
    this.termsText,
    this.pdfUrl,
    this.confirmedBy,
    this.confirmedAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.salesOrderNo,
    this.orderDate,
    this.billType = 'Credit',
    this.placeOfSupply,
    this.distance,
    this.grLrNo,
    this.destination,
    this.customerName,
    this.billingAddress,
    this.customerGstin,
    this.customerPhone,
    this.partyContactPerson,
    this.shippingName,
    this.shippingAddress,
    this.stateCode,
    this.salesman,
    this.remarks = 'Being Quotation Generated',
    this.leadId,
    this.revision = 1,
    this.paymentTerms,
    this.supplementaryTerms,
    this.supplementarySubtotal = 0.0,
  });

  factory Quotation.fromJson(Map<String, dynamic> json) {
    return Quotation(
      id: json['id'] as String? ?? '',
      pipelineId: json['pipeline_id'] as String? ?? '',
      quotationNumber: json['quotation_number'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      lineItems: (json['line_items'] as List<dynamic>? ?? [])
          .map((item) => LineItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      productSpecs: Map<String, dynamic>.from(
        json['product_specs'] as Map<String, dynamic>? ?? {},
      ),
      subtotal: (json['subtotal'] as num? ?? 0).toDouble(),
      cgstRate: (json['cgst_rate'] as num? ?? 9).toDouble(),
      sgstRate: (json['sgst_rate'] as num? ?? 9).toDouble(),
      cgstAmount: (json['cgst_amount'] as num? ?? 0).toDouble(),
      sgstAmount: (json['sgst_amount'] as num? ?? 0).toDouble(),
      igstAmount: (json['igst_amount'] as num? ?? 0).toDouble(),
      grandTotal: (json['grand_total'] as num? ?? 0).toDouble(),
      termsText: json['terms_text'] as String?,
      pdfUrl: json['pdf_url'] as String?,
      confirmedBy: json['confirmed_by'] as String?,
      confirmedAt: json['confirmed_at'] != null
          ? DateTime.tryParse(json['confirmed_at'] as String? ?? '')
          : null,
      status: QuotationStatus.fromString(json['status'] as String? ?? 'draft'),
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? (DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now())
          : DateTime.now(),
      salesOrderNo: json['sales_order_no'] as String?,
      orderDate: json['order_date'] != null
          ? DateTime.tryParse(json['order_date'] as String? ?? '')
          : null,
      billType: json['bill_type'] as String? ?? 'Credit',
      placeOfSupply: json['place_of_supply'] as String?,
      distance: json['distance'] != null ? (json['distance'] as num).toDouble() : null,
      grLrNo: json['gr_lr_no'] as String?,
      destination: json['destination'] as String?,
      customerName: json['customer_name'] as String?,
      billingAddress: json['billing_address'] as String?,
      customerGstin: json['customer_gstin'] as String?,
      customerPhone: json['customer_phone'] as String?,
      partyContactPerson: json['party_contact_person'] as String?,
      shippingName: json['shipping_name'] as String?,
      shippingAddress: json['shipping_address'] as String?,
      stateCode: json['state_code'] as int?,
      salesman: json['salesman'] as String?,
      remarks: json['remarks'] as String? ?? 'Being Quotation Generated',
      leadId: json['lead_id'] as String?,
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      paymentTerms: (json['payment_terms'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      supplementaryTerms: (json['supplementary_terms'] as List<dynamic>?)
          ?.map((e) => SupplementaryItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      supplementarySubtotal: (json['supplementary_subtotal'] as num? ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'pipeline_id': pipelineId,
    'product_id': productId,
    'line_items': lineItems.map((item) => item.toJson()).toList(),
    'product_specs': productSpecs,
    'subtotal': subtotal,
    'cgst_rate': cgstRate,
    'sgst_rate': sgstRate,
    'cgst_amount': cgstAmount,
    'sgst_amount': sgstAmount,
    'igst_amount': igstAmount,
    'grand_total': grandTotal,
    'terms_text': termsText,
    'status': status.dbValue,
    'sales_order_no': salesOrderNo,
    'order_date': orderDate?.toIso8601String(),
    'bill_type': billType,
    'place_of_supply': placeOfSupply,
    'distance': distance,
    'gr_lr_no': grLrNo,
    'destination': destination,
    'customer_name': customerName,
    'billing_address': billingAddress,
    'customer_gstin': customerGstin,
    'customer_phone': customerPhone,
    'party_contact_person': partyContactPerson,
    'shipping_name': shippingName,
    'shipping_address': shippingAddress,
    'state_code': stateCode,
    'salesman': salesman,
    'remarks': remarks,
    if (leadId != null) 'lead_id': leadId,
    'revision': revision,
    if (paymentTerms != null) 'payment_terms': paymentTerms,
    if (supplementaryTerms != null)
      'supplementary_terms': supplementaryTerms!.map((item) => item.toJson()).toList(),
    'supplementary_subtotal': supplementarySubtotal,
  };

  bool get isConfirmed => status == QuotationStatus.confirmed;
  bool get hasPdf => pdfUrl != null && pdfUrl!.isNotEmpty;
}

